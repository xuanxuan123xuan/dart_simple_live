import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:simple_live_core/src/common/core_cancellation.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/common/kuaishou_cooldown_evidence_tracker.dart';
import 'package:simple_live_core/src/common/kuaishou_live_link.dart';
import 'package:simple_live_core/src/common/kuaishou_request_coordinator.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';

/// 快手请求的来源（用于请求观测与后续协调器优先级）。
enum KuaishouRequestSource {
  /// 用户主动进房（点击房间卡片）
  userEnter,

  /// 多开格子加载：优先级接近用户进房，但仍需遵守请求间隔。
  multiRoom,

  /// 直播状态轮询 / 播放恢复
  roomStatusPolling,

  /// 播放链路内的恢复性重试
  playbackRecovery,

  /// 关注列表后台状态刷新
  followStatus,

  /// 弹幕凭证解析
  danmakuCredential,

  /// 手动解析 / 其他入口
  manual,

  /// 未标记来源
  unknown,
}

/// 快手响应错误分类（S2-T2）。
enum KuaishouErrorClassification {
  /// 无错误 / 正常响应。
  none,

  /// 403：无权限（可能是风控/挑战页）。
  forbidden,

  /// 429：请求过于频繁（明确限流）。
  rateLimited,

  /// 挑战页/验证码（页面特征识别）。
  challengePage,

  /// 其他 HTTP 错误。
  httpError,

  /// 网络层失败（连接/超时）。
  networkError,

  /// 登录 Cookie 已被明确拒绝或页面已回到登录态。
  credentialInvalid,
}

enum KuaishouAccountHealthEvent {
  rateLimited,
  securityChallenge,
  credentialInvalid,
}

class KuaishouAccountFallbackSession {
  const KuaishouAccountFallbackSession({
    required this.sessionKey,
    required this.cookie,
    required this.kww,
  });

  final String sessionKey;
  final String cookie;
  final String kww;
}

typedef KuaishouAccountFallbackProvider = KuaishouAccountFallbackSession?
    Function(String attemptedSessionKey);

abstract class KuaishouCategorySnapshotStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> snapshot);
}

/// 以 async-local 方式携带当前快手请求来源，供站点内部日志聚合使用。
/// 不改动 LiveSite 接口签名即可让调用方标记来源；未标记时回退 unknown。
class KuaishouRequestTrace {
  KuaishouRequestTrace._();

  static const _sourceKey = #kuaishouRequestSource;
  static const _scopeKey = #kuaishouRequestScope;
  static const _forceNetworkKey = #kuaishouForceNetwork;

  static KuaishouRequestSource get current =>
      Zone.current[_sourceKey] as KuaishouRequestSource? ??
      KuaishouRequestSource.unknown;

  static String? get scopeId => Zone.current[_scopeKey] as String?;

  static bool get forceNetwork =>
      Zone.current[_forceNetworkKey] as bool? ?? false;

  static Future<T> run<T>(
    KuaishouRequestSource source,
    Future<T> Function() action, {
    String? scopeId,
    bool forceNetwork = false,
  }) {
    return Zone.current.fork(zoneValues: {
      _sourceKey: source,
      if (scopeId != null) _scopeKey: scopeId,
      _forceNetworkKey: forceNetwork,
    }).run(action);
  }
}

class KuaishouSite extends LiveSite {
  static const int _liveSearchPageSize = 20;
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  KuaishouSite({
    Dio Function()? authenticatedDioFactory,
    CookieJar Function()? cookieJarFactory,
    KuaishouRequestCoordinator? coordinator,
    KuaishouCategorySnapshotStore? categorySnapshotStore,
  })  : _authenticatedDioFactory = authenticatedDioFactory ?? Dio.new,
        _cookieJarFactory = cookieJarFactory ?? CookieJar.new,
        _categorySnapshotStore = categorySnapshotStore,
        coordinator = coordinator ?? KuaishouRequestCoordinator() {
    id = "kuaishou";
    name = "快手直播";
  }

  static const String _legacySessionKey = 'legacy';
  final Map<String, _KuaishouAccountTransport> _accountTransports = {};
  String _activeAccountSessionKey = _legacySessionKey;
  bool _anonymousMode = false;

  _KuaishouAccountTransport get _activeTransport =>
      _transportFor(_activeAccountSessionKey);

  String get activeAccountSessionKey => _activeAccountSessionKey;
  bool get anonymousMode => _anonymousMode;

  /// Legacy accessors remain available for existing callers and tests. Values
  /// are routed to the currently active account transport.
  String get customCookie => _activeTransport.customCookie;
  set customCookie(String value) => _activeTransport.customCookie = value;

  String get customKww => _activeTransport.customKww;
  set customKww(String value) => _activeTransport.customKww = value;

  String get cookie => _activeTransport.cookie;
  set cookie(String value) => _activeTransport.cookie = value;

  Map<String, String> get cookieObj => _activeTransport.cookieObj;
  set cookieObj(Map<String, String> value) =>
      _activeTransport.cookieObj = value;

  /// 当前进程内正在执行中的快手详情请求数（观测用）。
  int activeDetailRequests = 0;

  /// 最近一次快手响应分类，供当前请求选择备用账号和错误展示使用。
  KuaishouErrorClassification get lastErrorClassification =>
      _activeTransport.lastErrorClassification;

  void Function(KuaishouAccountHealthEvent event)? onAccountHealthEvent;
  void Function(String sessionKey, KuaishouAccountHealthEvent event)?
      onAccountSessionHealthEvent;

  /// Supplies the other available account for one foreground room operation.
  /// The provider does not change the globally selected account.
  KuaishouAccountFallbackProvider? accountFallbackProvider;

  /// 快手敏感请求的进程级协调器：全局最小间隔、优先级、同房合并与短缓存。
  final KuaishouRequestCoordinator coordinator;

  final Dio Function() _authenticatedDioFactory;
  final CookieJar Function() _cookieJarFactory;
  final KuaishouCategorySnapshotStore? _categorySnapshotStore;
  final StreamController<List<LiveCategory>> _categoryUpdates =
      StreamController<List<LiveCategory>>.broadcast();
  Stream<List<LiveCategory>> get categoryUpdates => _categoryUpdates.stream;

  void cancelScope(String scopeId) => coordinator.cancelScope(scopeId);

  /// 房间详情成功缓存 TTL（短窗口复用，播放地址有效期未核实前取保守值）。
  static const Duration _detailCacheTtl = Duration(seconds: 15);

  /// 403/挑战页的连续凭据拒绝证据，按端点与 Cookie 会话隔离。
  _KuaishouAccountTransport _transportFor(String sessionKey) {
    return _accountTransports.putIfAbsent(
      sessionKey,
      () => _KuaishouAccountTransport(sessionKey),
    );
  }

  /// Selects one account slot while retaining every other slot's independent
  /// CookieJar, Dio, parsed-cookie state, DID state, and cache namespace.
  void activateAccountSession({
    required String sessionKey,
    required String cookie,
    required String kww,
  }) {
    final transport = _transportFor(sessionKey);
    if (transport.customCookie != cookie || transport.customKww != kww) {
      transport.resetCredential(cookie: cookie, kww: kww);
    }
    transport.hardBlocked = false;
    transport.cooldownUntil = null;
    transport.lastHealthEvent = null;
    _activeAccountSessionKey = sessionKey;
    _anonymousMode = false;
  }

  void activateAnonymousMode() {
    _activeAccountSessionKey = _legacySessionKey;
    _anonymousMode = true;
  }

  /// Test-only observability without exposing cookie values.
  Object? authenticatedDioIdentityFor(String sessionKey) =>
      _accountTransports[sessionKey]?.sessionDio;

  Object? cookieJarIdentityFor(String sessionKey) =>
      _accountTransports[sessionKey]?.sessionCookieJar;

  bool didReportAttemptedFor(String sessionKey) =>
      _accountTransports[sessionKey]?.didReportAttempted ?? false;

  /// 确保长期会话已初始化；customCookie 通过请求头随请求传入。
  void _ensureSession(_KuaishouAccountTransport transport) {
    if (transport.sessionDio != null) {
      return;
    }
    final dio = _authenticatedDioFactory();
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.sendTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 5);
    final cookieJar = _cookieJarFactory();
    dio.interceptors.add(CookieManager(cookieJar));
    transport.sessionDio = dio;
    transport.sessionCookieJar = cookieJar;
  }

  /// 账号切换 / 自定义 Cookie 变化时显式清空会话并重建，
  /// 避免旧账号 Cookie 污染新账号（冷启动方案 11 风险登记）。
  void resetCookieSession() {
    _activeTransport.resetCredential(
      cookie: _activeTransport.customCookie,
      kww: _activeTransport.customKww,
    );
  }

  static const List<String> _imageExtensions = [
    'svgz',
    'pjp',
    'png',
    'ico',
    'avif',
    'tiff',
    'tif',
    'jfif',
    'svg',
    'xbm',
    'pjpeg',
    'webp',
    'jpg',
    'jpeg',
    'bmp',
    'gif',
  ];

  Map<String, dynamic> get _headers => {
        'User-Agent': userAgent,
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        'connection': 'keep-alive',
        'sec-ch-ua': 'Google Chrome;v=120, Chromium;v=120, Not=A?Brand;v=24',
        'sec-ch-ua-platform': 'Windows',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-User': '?1',
      };

  Map<String, dynamic> _searchHeaders(String keyword) => {
        ..._headers,
        'accept': 'application/json, text/plain, */*',
        'referer':
            'https://live.kuaishou.com/search?keyword=${Uri.encodeComponent(keyword)}',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
      };

  Future<dynamic> _getPublicJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    required Map<String, dynamic> headers,
    CoreCancellation? cancellation,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final transport = _preferredCookieTransport();
    if (transport == null) {
      throw CoreError(
        '请先配置快手账号 Cookie',
        statusCode: 401,
        kind: CoreErrorKind.http,
      );
    }
    Future<dynamic> requestWith(_KuaishouAccountTransport selected) async {
      final requestHeaders = <String, dynamic>{...headers};
      final cookieHeader = _currentCookieHeaderFor(selected).trim();
      if (cookieHeader.isEmpty) {
        throw CoreError(
          '请先配置快手账号 Cookie',
          statusCode: 401,
          kind: CoreErrorKind.http,
        );
      }
      requestHeaders['cookie'] = cookieHeader;
      final result = await HttpClient.instance.getJson(
        url,
        queryParameters: queryParameters,
        header: requestHeaders,
        cancellation: cancellation,
        timeout: timeout,
      );
      _throwIfExplicitRateLimit(result);
      return result;
    }

    try {
      return await requestWith(transport);
    } catch (firstError, firstStackTrace) {
      final fallback = _preferredCookieTransport(excluding: transport);
      if (fallback != null) {
        return requestWith(fallback);
      }
      Error.throwWithStackTrace(firstError, firstStackTrace);
    }
  }

  _KuaishouAccountTransport? _preferredCookieTransport({
    _KuaishouAccountTransport? excluding,
  }) {
    final active = _activeTransport;
    if (!identical(active, excluding) &&
        _currentCookieHeaderFor(active).trim().isNotEmpty) {
      return active;
    }
    return _resolveFallbackTransport(excluding ?? active);
  }

  Map<String, dynamic> _headersWithCookieFor(
    _KuaishouAccountTransport transport,
  ) {
    final headers = <String, dynamic>{..._headers};
    final cookieValue = _currentCookieHeaderFor(transport);
    if (cookieValue.isNotEmpty) {
      headers['cookie'] = cookieValue;
    }
    return headers;
  }

  static String resolveServerKww(String cookie, String fallback) {
    for (final part in cookie.split(';')) {
      final item = part.trim();
      if (!item.startsWith('kwfv1=')) {
        continue;
      }
      final value = item.substring('kwfv1='.length).trim();
      if (value.isEmpty) {
        continue;
      }
      try {
        return '${Uri.decodeComponent(value)}###ssrc';
      } catch (_) {
        return '$value###ssrc';
      }
    }
    return fallback.trim();
  }

  static String resolveRoomTitle(Map room) {
    final liveStream =
        room["liveStream"] is Map ? room["liveStream"] as Map : const {};
    final gameInfo =
        room["gameInfo"] is Map ? room["gameInfo"] as Map : const {};
    final author = room["author"] is Map ? room["author"] as Map : const {};
    for (final value in [
      room["caption"],
      room["title"],
      liveStream["caption"],
      liveStream["title"],
      gameInfo["name"],
      author["name"],
    ]) {
      final title = value?.toString().trim() ?? '';
      if (title.isNotEmpty) {
        return title;
      }
    }
    return '';
  }

  static LiveStatusState resolveLiveState(Map room) {
    final liveStream = _resolveLiveStream(room);
    final liveStreamId = liveStream["id"]?.toString().trim() ?? '';
    if (liveStreamId.isNotEmpty ||
        _isLiveFlag(room["isLiving"]) ||
        _isLiveFlag(room["living"]) ||
        _isLiveFlag(liveStream["isLiving"]) ||
        _isLiveFlag(liveStream["living"])) {
      return LiveStatusState.live;
    }
    // Kuaishou sometimes returns an HTTP 200 room page whose payload is an
    // error snapshot (for example errorType=2 / "请求过快，请稍后重试").
    // Such snapshots also carry isLiving=false, but that is not evidence that
    // the broadcaster went offline.
    if (_hasRoomError(room)) {
      return LiveStatusState.unknown;
    }
    if (_isOfflineFlag(room["isLiving"]) ||
        _isOfflineFlag(room["living"]) ||
        _isOfflineFlag(liveStream["isLiving"]) ||
        _isOfflineFlag(liveStream["living"])) {
      return LiveStatusState.offline;
    }
    return LiveStatusState.unknown;
  }

  static bool _hasRoomError(Map room) {
    final error = room["errorType"];
    if (error is Map) {
      if (error.isEmpty) return false;
      final type = error["type"];
      final normalizedType = type?.toString().trim() ?? '';
      if (normalizedType.isNotEmpty && normalizedType != '0') {
        return true;
      }
      for (final key in const ["title", "content", "url"]) {
        if (error[key]?.toString().trim().isNotEmpty == true) {
          return true;
        }
      }
      return false;
    }
    return error?.toString().trim().isNotEmpty == true;
  }

  static LiveStatusState resolvePlayListState(dynamic playList) {
    if (playList is! List || playList.isEmpty) {
      return LiveStatusState.unknown;
    }
    final states =
        playList.whereType<Map>().map(resolveLiveState).toList(growable: false);
    if (states.any((state) => state == LiveStatusState.live)) {
      return LiveStatusState.live;
    }
    if (states.isNotEmpty &&
        states.every((state) => state == LiveStatusState.offline)) {
      return LiveStatusState.offline;
    }
    return LiveStatusState.unknown;
  }

  static bool resolveLiveStatus(Map room) =>
      resolveLiveState(room) == LiveStatusState.live;

  static Map _resolveLiveStream(Map room) {
    final nested = room["liveStream"];
    if (nested is Map && nested.isNotEmpty) {
      return nested;
    }
    return room;
  }

  static bool _isLiveFlag(dynamic value) {
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == "true";
  }

  static bool _isOfflineFlag(dynamic value) {
    return value == false ||
        value == 0 ||
        value?.toString().toLowerCase() == "false";
  }

  static List<String> extractPlayableUrls(dynamic value) {
    final urls = <String>[];
    final seen = <String>{};

    void collect(dynamic current) {
      if (current is String) {
        final url = current.trim();
        final uri = Uri.tryParse(url);
        final scheme = uri?.scheme.toLowerCase();
        if (url.isNotEmpty &&
            (scheme == 'http' || scheme == 'https' || scheme == 'rtmp') &&
            seen.add(url)) {
          urls.add(url);
        }
        return;
      }
      if (current is Map) {
        for (final child in current.values) {
          collect(child);
        }
        return;
      }
      if (current is Iterable) {
        for (final child in current) {
          collect(child);
        }
      }
    }

    collect(value);
    return urls;
  }

  @override
  LiveDanmaku getDanmaku() => _anonymousMode
      ? LiveDanmaku()
      : KuaishouDanmaku(
          credentialCooldownCheck: () =>
              coordinator.inCooldown ||
              _activeTransport.hardBlocked ||
              (_activeTransport.cooldownUntil?.isAfter(DateTime.now()) ??
                  false),
        );

  // ==================== 分类 ====================

  static const int _categorySnapshotVersion = 1;
  static const Duration _categorySnapshotTtl = Duration(hours: 12);
  static const String _categoryRefreshScope = 'kuaishou:category-refresh';

  List<LiveCategory> _emptyCategoryRoots() => <LiveCategory>[
        LiveCategory(id: "1", name: "热门", children: []),
        LiveCategory(id: "2", name: "网游", children: []),
        LiveCategory(id: "3", name: "单机", children: []),
        LiveCategory(id: "4", name: "手游", children: []),
        LiveCategory(id: "5", name: "棋牌", children: []),
        LiveCategory(id: "6", name: "娱乐", children: []),
        LiveCategory(id: "7", name: "综合", children: []),
        LiveCategory(id: "8", name: "文化", children: []),
      ];

  @override
  Future<List<LiveCategory>> getCategores() async {
    final cached = await _readCategorySnapshot();
    if (cached != null) {
      if (DateTime.now().difference(cached.savedAt) > _categorySnapshotTtl) {
        unawaited(refreshCategories().catchError((Object error) {
          CoreLog.i('[ks-category] background refresh failed: $error');
          return cached.categories;
        }));
      }
      return cached.categories;
    }
    return refreshCategories();
  }

  Future<List<LiveCategory>> refreshCategories() async {
    final categories = _emptyCategoryRoots();
    for (final category in categories) {
      category.children.addAll(await _getAllSubCategories(category));
    }
    if (categories.length != 8 ||
        categories.any((category) => category.children.isEmpty)) {
      throw CoreError(
        '快手分区目录不完整，已保留旧缓存',
        kind: CoreErrorKind.response,
      );
    }
    final store = _categorySnapshotStore;
    if (store != null) {
      await store.write({
        'version': _categorySnapshotVersion,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'categories': categories.map((item) => item.toJson()).toList(),
      });
    }
    _categoryUpdates.add(categories);
    return categories;
  }

  Future<_KuaishouCategorySnapshot?> _readCategorySnapshot() async {
    final raw = await _categorySnapshotStore?.read();
    if (raw == null || raw['version'] != _categorySnapshotVersion) {
      return null;
    }
    try {
      final savedAt = DateTime.parse(raw['savedAt'].toString()).toLocal();
      final list = raw['categories'];
      if (list is! List || list.length != 8) return null;
      final categories = list
          .map((item) => LiveCategory.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(growable: false);
      if (categories.any((category) => category.children.isEmpty)) return null;
      return _KuaishouCategorySnapshot(savedAt, categories);
    } catch (error) {
      CoreLog.i('[ks-category] invalid snapshot: $error');
      return null;
    }
  }

  Future<List<LiveSubCategory>> _getAllSubCategories(
    LiveCategory category,
  ) async {
    final allSubs = <LiveSubCategory>[];
    final seen = <String>{};
    for (var page = 1; page <= 10; page++) {
      final result = await _getSubCategories(category, page, 50);
      for (final sub in result.items) {
        if (seen.add('${sub.parentId}:${sub.id}')) {
          allSubs.add(sub);
        }
      }
      if (!result.hasMore) break;
      if (page == 10) {
        throw CoreError(
          '快手分区目录超过分页上限',
          kind: CoreErrorKind.response,
        );
      }
    }
    return allSubs;
  }

  Future<_KuaishouSubCategoryPage> _getSubCategories(
    LiveCategory category,
    int page,
    int pageSize,
  ) async {
    var result = await coordinator.schedule<dynamic>(
      priority: KuaishouRequestPriority.catalogBackground,
      key: 'http:category:${category.id}:$page:$pageSize',
      traffic: KuaishouRequestTraffic.publicApi,
      scopeId: _categoryRefreshScope,
      timeout: const Duration(seconds: 8),
      task: () => _getPublicJson(
        "https://live.kuaishou.com/live_api/category/data",
        queryParameters: {"type": category.id, "page": page, "size": pageSize},
        headers: _headers,
      ),
    );
    _throwIfExplicitRateLimit(result);
    if (result is! Map || result['data'] is! Map) {
      throw CoreError('快手分区目录响应格式错误', kind: CoreErrorKind.response);
    }
    final data = result['data'] as Map;
    final list = data['list'];
    if (list is! List || _parseResponseBoolean(data['hasMore']) == null) {
      throw CoreError('快手分区目录分页字段缺失', kind: CoreErrorKind.response);
    }
    final subs = <LiveSubCategory>[];
    for (final item in list) {
      if (item is! Map || item['id'] == null || item['name'] == null) {
        throw CoreError('快手分区目录条目格式错误', kind: CoreErrorKind.response);
      }
      subs.add(
        LiveSubCategory(
          id: item["id"].toString(),
          name: item["name"] ?? "",
          parentId: category.id,
          pic: item["poster"],
        ),
      );
    }
    return _KuaishouSubCategoryPage(
      items: subs,
      hasMore: _parseResponseBoolean(data['hasMore'])!,
    );
  }

  // ==================== 分类直播间列表 ====================

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final parentId = int.tryParse(category.parentId) ?? 0;
    if (parentId < 1 || parentId > 8) {
      throw CoreError(
        '快手分区父级编号无效',
        kind: CoreErrorKind.response,
      );
    }
    final api = parentId >= 1 && parentId <= 5
        ? "https://live.kuaishou.com/live_api/gameboard/list"
        : "https://live.kuaishou.com/live_api/non-gameboard/list";

    var result = await coordinator.schedule<dynamic>(
      priority: KuaishouRequestPriority.interactivePublic,
      key: 'http:category_rooms:${category.id}:$page',
      traffic: KuaishouRequestTraffic.publicApi,
      scopeId: KuaishouRequestTrace.scopeId,
      timeout: const Duration(seconds: 8),
      task: () => _getPublicJson(
        api,
        queryParameters: {
          "filterType": 0,
          "pageSize": 20,
          "gameId": category.id,
          "page": page,
        },
        headers: _headers,
      ),
    );
    _throwIfExplicitRateLimit(result);
    if (result is! Map || result['data'] is! Map) {
      throw CoreError('快手分区直播间响应格式错误', kind: CoreErrorKind.response);
    }
    final data = result['data'] as Map;
    final list = data['list'];
    final hasMore = _parseResponseBoolean(data['hasMore']);
    if (list is! List || hasMore == null) {
      throw CoreError('快手分区直播间分页字段缺失', kind: CoreErrorKind.response);
    }
    var items = <LiveRoomItem>[];
    for (var item in list) {
      var cover = item['poster']?.toString() ?? '';
      if (cover.isNotEmpty && !isImageUrl(cover)) {
        cover = '$cover.jpg';
      }
      items.add(
        LiveRoomItem(
          roomId: item["author"]["id"]?.toString() ?? '',
          title: item['caption']?.toString() ?? '',
          cover: cover,
          userName: item["author"]["name"]?.toString() ?? '',
          online: _parseInt(item["watchingCount"]),
        ),
      );
    }

    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  // ==================== 推荐直播间 ====================

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await coordinator.schedule<dynamic>(
      priority: KuaishouRequestPriority.interactivePublic,
      key: 'http:home:$page',
      traffic: KuaishouRequestTraffic.publicApi,
      scopeId: KuaishouRequestTrace.scopeId,
      timeout: const Duration(seconds: 8),
      task: () => _getPublicJson(
        "https://live.kuaishou.com/live_api/home/list",
        headers: _headers,
      ),
    );
    _throwIfExplicitRateLimit(result);
    if (result is! Map || result['data'] is! Map) {
      throw CoreError('快手推荐响应格式错误', kind: CoreErrorKind.response);
    }
    final list = (result['data'] as Map)['list'];
    if (list is! List) {
      throw CoreError('快手推荐列表字段缺失', kind: CoreErrorKind.response);
    }
    var items = <LiveRoomItem>[];

    for (var item in list) {
      for (var sitem in item["gameLiveInfo"] ?? []) {
        for (var titem in sitem["liveInfo"] ?? []) {
          var author = titem["author"];
          var gameInfo = titem["gameInfo"];
          var cover = gameInfo['poster']?.toString() ?? '';
          items.add(
            LiveRoomItem(
              roomId: author["id"]?.toString() ?? '',
              title: resolveRoomTitle(titem),
              cover: cover,
              userName: author["name"]?.toString() ?? '',
              online: _parseInt(titem["watchingCount"]),
            ),
          );
        }
      }
    }
    if (items.any((item) => item.online > 0)) {
      items.sort((a, b) => b.online.compareTo(a.online));
    }

    return LiveCategoryResult(hasMore: false, items: items);
  }

  // ==================== 搜索 ====================

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async {
    Object? primaryError;
    try {
      final result = await _searchLiveStreams(
        keyword,
        page: page,
        cancellation: cancellation,
      );
      return result;
    } on CoreCancelledError {
      rethrow;
    } catch (error) {
      primaryError = error;
    }

    if (page > 1) {
      throw _searchFailure('直播间', primaryError);
    }

    try {
      return await _searchRoomsByOverview(
        keyword,
        cancellation: cancellation,
      );
    } on CoreCancelledError {
      rethrow;
    } catch (fallbackError) {
      throw _searchFallbackFailure('直播间', primaryError, fallbackError);
    }
  }

  Future<LiveSearchRoomResult> _searchLiveStreams(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async {
    final result = await coordinator.schedule<dynamic>(
      priority: KuaishouRequestPriority.interactivePublic,
      key: 'http:search_live:${keyword.hashCode}:$page',
      traffic: KuaishouRequestTraffic.publicApi,
      scopeId: KuaishouRequestTrace.scopeId ?? 'kuaishou:search',
      timeout: const Duration(seconds: 8),
      task: () => _getPublicJson(
        "https://live.kuaishou.com/live_api/search/liveStream",
        queryParameters: {
          "keyword": keyword,
          "page": page,
          "count": _liveSearchPageSize,
          "ussid": "",
        },
        headers: _searchHeaders(keyword),
        cancellation: cancellation,
      ),
    );
    _throwIfExplicitRateLimit(result);

    if (result is! Map) {
      throw _invalidSearchResponse('直播间');
    }
    final data = result["data"];
    if (data is! Map) {
      throw _invalidSearchResponse('直播间');
    }
    if (data["result"] != 1) {
      throw _searchFailure('直播间', data["message"] ?? data["msg"]);
    }

    final list = data["list"];
    if (list is! List) {
      throw _invalidSearchResponse('直播间');
    }
    final items = <LiveRoomItem>[];
    for (final item in list) {
      if (item is! Map) {
        throw _invalidSearchResponse('直播间');
      }
      final room = _parseSearchLiveRoom(item);
      if (room.roomId.isNotEmpty) {
        items.add(room);
      }
    }

    return LiveSearchRoomResult(
      items: items,
      metadata: LiveSearchMetadata(
        continuation: _resolveSearchContinuation(
          data,
          page: page,
          pageSize: _liveSearchPageSize,
        ),
        origin: SearchOrigin.native,
      ),
    );
  }

  Future<LiveSearchRoomResult> _searchRoomsByOverview(
    String keyword, {
    CoreCancellation? cancellation,
  }) async {
    final overview = await _getSearchOverview(
      keyword,
      cancellation: cancellation,
    );
    final liveStreams = _findOverviewSectionList(overview, "liveStreams");
    final items = <LiveRoomItem>[];
    for (final item in liveStreams) {
      if (item is! Map) {
        throw _invalidSearchResponse('概览直播间');
      }
      final room = _parseSearchLiveRoom(item);
      if (room.roomId.isNotEmpty) {
        items.add(room);
      }
    }
    return LiveSearchRoomResult(
      items: items,
      metadata: LiveSearchMetadata(
        continuation: items.isEmpty
            ? SearchContinuation.done
            : SearchContinuation.unknown,
        origin: SearchOrigin.fallback,
      ),
    );
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async {
    Object? primaryError;
    try {
      final result = await _searchAnchors(
        keyword,
        page: page,
        cancellation: cancellation,
      );
      return result;
    } on CoreCancelledError {
      rethrow;
    } catch (error) {
      primaryError = error;
    }

    if (page > 1) {
      throw _searchFailure('主播', primaryError);
    }

    try {
      return await _searchAnchorsByOverview(
        keyword,
        cancellation: cancellation,
      );
    } on CoreCancelledError {
      rethrow;
    } catch (fallbackError) {
      throw _searchFallbackFailure('主播', primaryError, fallbackError);
    }
  }

  Future<LiveSearchAnchorResult> _searchAnchors(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async {
    final result = await coordinator.schedule<dynamic>(
      priority: KuaishouRequestPriority.interactivePublic,
      key: 'http:search_author:${keyword.hashCode}:$page',
      traffic: KuaishouRequestTraffic.publicApi,
      scopeId: KuaishouRequestTrace.scopeId ?? 'kuaishou:search',
      timeout: const Duration(seconds: 8),
      task: () => _getPublicJson(
        "https://live.kuaishou.com/live_api/search/author",
        queryParameters: {
          "key": keyword,
          "keyword": keyword,
          "page": page,
          "count": 15,
          "ussid": "",
          "lssid": "",
        },
        headers: _searchHeaders(keyword),
        cancellation: cancellation,
      ),
    );
    _throwIfExplicitRateLimit(result);

    if (result is! Map) {
      throw _invalidSearchResponse('主播');
    }
    final data = result["data"];
    if (data is! Map) {
      throw _invalidSearchResponse('主播');
    }
    if (data["result"] != 1) {
      throw _searchFailure('主播', data["message"] ?? data["msg"]);
    }

    final list = data["list"];
    if (list is! List) {
      throw _invalidSearchResponse('主播');
    }
    final items = <LiveAnchorItem>[];
    for (final item in list) {
      if (item is! Map) {
        throw _invalidSearchResponse('主播');
      }
      final anchor = _parseSearchAnchor(item);
      if (anchor.roomId.isNotEmpty) {
        items.add(anchor);
      }
    }

    return LiveSearchAnchorResult(
      items: items,
      metadata: LiveSearchMetadata(
        continuation: _resolveSearchContinuation(
          data,
          page: page,
          pageSize: 15,
        ),
        origin: SearchOrigin.native,
      ),
    );
  }

  Future<LiveSearchAnchorResult> _searchAnchorsByOverview(
    String keyword, {
    CoreCancellation? cancellation,
  }) async {
    final overview = await _getSearchOverview(
      keyword,
      cancellation: cancellation,
    );
    final authors = _findOverviewSectionList(overview, "authors");
    final items = <LiveAnchorItem>[];
    for (final item in authors) {
      if (item is! Map) {
        throw _invalidSearchResponse('概览主播');
      }
      final anchor = _parseSearchAnchor(item);
      if (anchor.roomId.isNotEmpty) {
        items.add(anchor);
      }
    }
    return LiveSearchAnchorResult(
      items: items,
      metadata: LiveSearchMetadata(
        continuation: items.isEmpty
            ? SearchContinuation.done
            : SearchContinuation.unknown,
        origin: SearchOrigin.fallback,
      ),
    );
  }

  Future<Map> _getSearchOverview(
    String keyword, {
    CoreCancellation? cancellation,
  }) async {
    final result = await coordinator.schedule<dynamic>(
      priority: KuaishouRequestPriority.interactivePublic,
      key: 'http:search_overview:${keyword.hashCode}',
      traffic: KuaishouRequestTraffic.publicApi,
      scopeId: KuaishouRequestTrace.scopeId ?? 'kuaishou:search',
      timeout: const Duration(seconds: 8),
      task: () => _getPublicJson(
        "https://live.kuaishou.com/live_api/search/overview",
        queryParameters: {"keyword": keyword, "ussid": ""},
        headers: _searchHeaders(keyword),
        cancellation: cancellation,
      ),
    );
    _throwIfExplicitRateLimit(result);
    if (result is! Map || result["data"] is! Map) {
      throw _invalidSearchResponse('概览');
    }
    return result["data"] as Map;
  }

  SearchContinuation _resolveSearchContinuation(
    Map data, {
    required int page,
    int? pageSize,
  }) {
    for (final key in const <String>[
      'hasMore',
      'hasNext',
      'hasNextPage',
    ]) {
      final value = _parseSearchBoolean(data[key]);
      if (value != null) {
        return value ? SearchContinuation.more : SearchContinuation.done;
      }
    }

    final nextPage = _parseSearchNonNegativeInt(data['nextPage']);
    if (nextPage != null) {
      return nextPage > page
          ? SearchContinuation.more
          : SearchContinuation.done;
    }

    for (final key in const <String>['totalPage', 'pageCount', 'totalPages']) {
      final totalPages = _parseSearchNonNegativeInt(data[key]);
      if (totalPages != null) {
        return page < totalPages
            ? SearchContinuation.more
            : SearchContinuation.done;
      }
    }

    if (pageSize != null) {
      for (final key in const <String>['total', 'totalCount', 'totalSize']) {
        final total = _parseSearchNonNegativeInt(data[key]);
        if (total != null) {
          return page * pageSize < total
              ? SearchContinuation.more
              : SearchContinuation.done;
        }
      }
    }
    return SearchContinuation.unknown;
  }

  bool? _parseSearchBoolean(dynamic value) {
    if (value is bool) return value;
    if (value is num) {
      if (value == 1) return true;
      if (value == 0) return false;
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return null;
  }

  int? _parseSearchNonNegativeInt(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  CoreError _invalidSearchResponse(String searchType) {
    return CoreError(
      '快手$searchType搜索响应格式错误',
      kind: CoreErrorKind.response,
    );
  }

  CoreError _searchFailure(String searchType, Object? cause) {
    if (cause is CoreError) return cause;
    return CoreError(
      '快手$searchType搜索失败',
      kind: CoreErrorKind.search,
      cause: cause,
    );
  }

  CoreError _searchFallbackFailure(
    String searchType,
    Object primaryError,
    Object fallbackError,
  ) {
    return CoreError(
      '快手$searchType搜索的主接口和概览备用接口均失败',
      kind: CoreErrorKind.search,
      cause: <Object>[primaryError, fallbackError],
    );
  }

  List _findOverviewSectionList(Map overview, String type) {
    final sections = overview["list"];
    if (sections is! List) {
      throw _invalidSearchResponse('概览');
    }
    for (final section in sections) {
      if (section is! Map) {
        throw _invalidSearchResponse('概览');
      }
      if (section["type"] == type) {
        final list = section["list"];
        if (list is! List) {
          throw _invalidSearchResponse('概览');
        }
        return list;
      }
    }
    return const [];
  }

  LiveRoomItem _parseSearchLiveRoom(dynamic item) {
    if (item is! Map) {
      return LiveRoomItem(roomId: '', title: '', cover: '', userName: '');
    }

    var author = item["author"] is Map ? item["author"] as Map : {};
    var gameInfo = item["gameInfo"] is Map ? item["gameInfo"] as Map : {};
    var cover = item["poster"]?.toString() ??
        item["coverUrl"]?.toString() ??
        gameInfo["poster"]?.toString() ??
        '';
    if (cover.isNotEmpty && !isImageUrl(cover)) {
      cover = '$cover.jpg';
    }

    return LiveRoomItem(
      roomId: author["id"]?.toString() ??
          item["authorId"]?.toString() ??
          item["userId"]?.toString() ??
          '',
      title: item["caption"]?.toString() ??
          item["title"]?.toString() ??
          author["name"]?.toString() ??
          '',
      cover: cover,
      userName:
          author["name"]?.toString() ?? item["userName"]?.toString() ?? '',
      online: _parseInt(item["watchingCount"]),
    );
  }

  LiveAnchorItem _parseSearchAnchor(dynamic item) {
    if (item is! Map) {
      return LiveAnchorItem(
        roomId: '',
        avatar: '',
        userName: '',
        liveStatus: false,
      );
    }

    return LiveAnchorItem(
      roomId: item["id"]?.toString() ?? '',
      avatar: item["avatar"]?.toString() ?? '',
      userName: item["name"]?.toString() ?? '',
      liveStatus: item["living"] == true,
    );
  }

  // ==================== 房间详情 ====================

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) {
    return _getRoomDetailWithinBudget(roomId).timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw CoreError(
        '快手直播间加载超时，请重试',
        kind: CoreErrorKind.network,
      ),
    );
  }

  Future<LiveRoomDetail> _getRoomDetailWithinBudget(String roomId) async {
    final source = KuaishouRequestTrace.current;
    if (_isUserTriggered(source)) {
      coordinator.cancelScope(_categoryRefreshScope);
      coordinator.cancelScope('kuaishou:follow-refresh');
      coordinator.cancelScope('kuaishou:search');
    }
    final firstTransport = _preferredCookieTransport();
    if (firstTransport == null) {
      throw CoreError(
        '请先配置快手账号 Cookie',
        statusCode: 401,
        kind: CoreErrorKind.http,
      );
    }
    try {
      return await _getRoomDetailForTransport(
        roomId,
        source: source,
        transport: firstTransport,
      );
    } catch (firstError, firstStackTrace) {
      // Follow refresh owns account failover at the batch level. Retrying the
      // secondary account here would make every failed room issue twice.
      if (source == KuaishouRequestSource.followStatus) {
        Error.throwWithStackTrace(firstError, firstStackTrace);
      }
      final fallbackTransport =
          _preferredCookieTransport(excluding: firstTransport);
      if (fallbackTransport != null) {
        return _getRoomDetailForTransport(
          roomId,
          source: source,
          transport: fallbackTransport,
        );
      }
      Error.throwWithStackTrace(firstError, firstStackTrace);
    }
  }

  _KuaishouAccountTransport? _resolveFallbackTransport(
    _KuaishouAccountTransport attempted,
  ) {
    final active = _activeTransport;
    if (!identical(active, attempted) &&
        active.sessionKey != attempted.sessionKey &&
        _currentCookieHeaderFor(active).isNotEmpty) {
      return active;
    }

    final fallback = accountFallbackProvider?.call(attempted.sessionKey);
    if (fallback == null ||
        fallback.sessionKey == attempted.sessionKey ||
        fallback.cookie.trim().isEmpty) {
      return null;
    }
    final transport = _transportFor(fallback.sessionKey);
    if (transport.customCookie != fallback.cookie ||
        transport.customKww != fallback.kww) {
      transport.resetCredential(
        cookie: fallback.cookie,
        kww: fallback.kww,
      );
    }
    return transport;
  }

  Future<LiveRoomDetail> _getRoomDetailForTransport(
    String roomId, {
    required KuaishouRequestSource source,
    required _KuaishouAccountTransport transport,
    bool requireLive = false,
  }) {
    return coordinator.coalesce(
      key: '${transport.cacheNamespace}:room_detail:$roomId:'
          '${requireLive ? "live" : "any"}',
      cacheTtl: roomDetailCacheTtlForSource(source),
      bypassCache: KuaishouRequestTrace.forceNetwork,
      task: () => _fetchRoomDetailUncoordinated(
        roomId,
        transport: transport,
        requireLive: requireLive,
      ),
    );
  }

  static bool _isUserTriggered(KuaishouRequestSource source) =>
      source == KuaishouRequestSource.userEnter ||
      source == KuaishouRequestSource.manual;

  /// Returns the detail-cache policy for a request source.
  ///
  /// Polling, playback recovery, and credential refresh need a fresh detail
  /// response, while coordinator pending de-duplication remains active.
  static Duration? roomDetailCacheTtlForSource(KuaishouRequestSource source) {
    switch (source) {
      case KuaishouRequestSource.roomStatusPolling:
      case KuaishouRequestSource.playbackRecovery:
      case KuaishouRequestSource.danmakuCredential:
        return null;
      case KuaishouRequestSource.userEnter:
      case KuaishouRequestSource.multiRoom:
      case KuaishouRequestSource.followStatus:
      case KuaishouRequestSource.manual:
      case KuaishouRequestSource.unknown:
        return _detailCacheTtl;
    }
  }

  /// 把请求来源映射为协调器优先级。
  KuaishouRequestPriority _priorityForSource(KuaishouRequestSource source) {
    switch (source) {
      case KuaishouRequestSource.userEnter:
      case KuaishouRequestSource.manual:
        return KuaishouRequestPriority.userEnter;
      case KuaishouRequestSource.multiRoom:
        return KuaishouRequestPriority.userEnter;
      case KuaishouRequestSource.playbackRecovery:
        return KuaishouRequestPriority.playbackRecovery;
      case KuaishouRequestSource.danmakuCredential:
        return KuaishouRequestPriority.danmakuCredential;
      case KuaishouRequestSource.roomStatusPolling:
      case KuaishouRequestSource.unknown:
        return KuaishouRequestPriority.roomStatus;
      case KuaishouRequestSource.followStatus:
        return KuaishouRequestPriority.followRefresh;
    }
  }

  /// 实际的房间详情抓取（已被协调器调度包裹，不再处理合并/缓存）。
  Future<LiveRoomDetail> _fetchRoomDetailUncoordinated(
    String roomId, {
    required _KuaishouAccountTransport transport,
    bool requireLive = false,
  }) async {
    final sessionEpoch = transport.epoch;
    final stopwatch = Stopwatch()..start();
    activeDetailRequests += 1;
    final source = KuaishouRequestTrace.current;
    final maskedRoom = _maskRoomId(roomId);
    // 本次请求开始前重置错误分类，避免沿用上一次请求的 403/429 分类
    // 造成误报（页面解析失败时应按本次实际响应分类）。
    transport.lastErrorClassification = KuaishouErrorClassification.none;
    transport.lastHealthEvent = null;
    CoreLog.i(
      '[ks-request] start endpoint=room_detail room=$maskedRoom '
      'source=${source.name} concurrency=$activeDetailRequests',
    );
    try {
      final url = KuaishouLiveLink.publicRoomUrl(roomId);
      final prefetchedPage = await _getCookie(
        url,
        roomId: roomId,
        transport: transport,
      );
      _ensureCurrentSession(transport, sessionEpoch);
      final prefetchMs = stopwatch.elapsedMilliseconds;

      LiveRoomDetail? detail;
      if (prefetchedPage != null && prefetchedPage.isNotEmpty) {
        detail = await _parseRoomDetail(
          prefetchedPage,
          roomId,
          transport: transport,
        );
        _ensureCurrentSession(transport, sessionEpoch);
      }
      if (_needsAuthenticatedRoomPage(detail) &&
          _currentCookieHeaderFor(transport).isNotEmpty) {
        CoreLog.i(
          '[ks-request] fallback=with_cookie room=$maskedRoom '
          'source=${source.name} prefetchMs=$prefetchMs',
        );
        detail = await _loadRoomDetail(
          url: url,
          roomId: roomId,
          headers: _headersWithCookieFor(transport),
          transport: transport,
          sessionEpoch: sessionEpoch,
        );
        _ensureCurrentSession(transport, sessionEpoch);
      }

      if (!_isCompleteRoomDetail(detail, requireLive: requireLive)) {
        final isLiveWithoutPlayback =
            detail?.resolvedLiveStatus == LiveStatusState.live &&
                extractPlayableUrls(detail?.data).isEmpty;
        final isRequiredLiveMissing = requireLive &&
            detail?.resolvedLiveStatus == LiveStatusState.offline;
        CoreLog.i(
          '[ks-request] fail endpoint=room_detail room=$maskedRoom '
          'source=${source.name} totalMs=${stopwatch.elapsedMilliseconds} '
          'reason=${isLiveWithoutPlayback ? "playback_missing" : isRequiredLiveMissing ? "live_missing" : "parse_failed"} '
          'class=${transport.lastErrorClassification.name}',
        );
        final classification = transport.lastErrorClassification;
        throw CoreError(
          isLiveWithoutPlayback || isRequiredLiveMissing
              ? "当前快手账号未取得直播详情，请稍后重试"
              : "快手直播间详情解析失败，请稍后重试",
          statusCode: classification == KuaishouErrorClassification.forbidden
              ? 403
              : classification == KuaishouErrorClassification.challengePage
                  ? 403
                  : classification == KuaishouErrorClassification.rateLimited
                      ? 429
                      : 0,
          kind: classification == KuaishouErrorClassification.forbidden ||
                  classification == KuaishouErrorClassification.challengePage ||
                  classification == KuaishouErrorClassification.rateLimited ||
                  classification ==
                      KuaishouErrorClassification.credentialInvalid
              ? CoreErrorKind.http
              : CoreErrorKind.response,
        );
      }

      // Completeness guarantees a non-null detail here; partial responses have
      // already failed and therefore cannot enter the completed-value cache.
      final completeDetail = detail!;

      if (source == KuaishouRequestSource.userEnter ||
          source == KuaishouRequestSource.manual) {
        unawaited(
          _registerDid(
            transport: transport,
            sessionEpoch: sessionEpoch,
            categoryId: completeDetail.categoryId,
            categoryName: completeDetail.categoryName,
          ),
        );
      }
      CoreLog.i(
        '[ks-request] done endpoint=room_detail room=$maskedRoom '
        'source=${source.name} '
        'status=${completeDetail.liveStatusState?.name ?? "unknown"} '
        'totalMs=${stopwatch.elapsedMilliseconds}',
      );
      return completeDetail;
    } finally {
      activeDetailRequests -= 1;
    }
  }

  static bool _needsAuthenticatedRoomPage(LiveRoomDetail? detail) {
    if (detail == null) return true;
    switch (detail.resolvedLiveStatus) {
      case LiveStatusState.live:
        return extractPlayableUrls(detail.data).isEmpty;
      case LiveStatusState.unknown:
        return true;
      case LiveStatusState.offline:
        return false;
    }
  }

  static bool _isCompleteRoomDetail(
    LiveRoomDetail? detail, {
    bool requireLive = false,
  }) {
    if (detail == null) return false;
    switch (detail.resolvedLiveStatus) {
      case LiveStatusState.live:
        return extractPlayableUrls(detail.data).isNotEmpty;
      case LiveStatusState.offline:
        return !requireLive;
      case LiveStatusState.unknown:
        return false;
    }
  }

  void _ensureCurrentSession(
    _KuaishouAccountTransport transport,
    int sessionEpoch,
  ) {
    if (sessionEpoch != transport.epoch) {
      throw KuaishouCooldownError('快手 Cookie 会话已重置');
    }
  }

  /// 脱敏 roomId：只保留短哈希，避免日志中出现完整房间号。
  static String _maskRoomId(String roomId) {
    if (roomId.isEmpty) return '';
    final hash = roomId.hashCode.toRadixString(16);
    return 'room#$hash';
  }

  Future<LiveRoomDetail?> _loadRoomDetail({
    required String url,
    required String roomId,
    required Map<String, dynamic> headers,
    required _KuaishouAccountTransport transport,
    required int sessionEpoch,
  }) async {
    final maskedRoom = _maskRoomId(roomId);
    final stopwatch = Stopwatch()..start();
    final source = KuaishouRequestTrace.current;
    final authenticated = headers['cookie']?.toString().isNotEmpty == true;
    try {
      Future<String> request() {
        if (authenticated) {
          _ensureTransportAvailable(transport, source);
        }
        return HttpClient.instance.getText(
          url,
          queryParameters: const {},
          header: headers,
          timeout: const Duration(seconds: 5),
        );
      }

      // Follow refresh is bounded by the app-level 2->4 adaptive limiter.
      // Bypass the single coordinator lane so its workers are truly parallel.
      final resultText = source == KuaishouRequestSource.followStatus
          ? await request()
          : await coordinator.schedule<String>(
              priority: _priorityForSource(source),
              key: '${transport.cacheNamespace}:http:room_page:'
                  '${authenticated ? "auth" : "anon"}:$roomId',
              logLabel: maskedRoom,
              scopeId: KuaishouRequestTrace.scopeId,
              timeout: const Duration(seconds: 5),
              task: request,
            );
      _ensureCurrentSession(transport, sessionEpoch);
      _throwIfExplicitRateLimit(resultText);
      if (authenticated && looksLikeCredentialInvalidPage(resultText)) {
        throw const _KuaishouCredentialInvalidException();
      }
      final hasInitialState = resultText.contains('window.__INITIAL_STATE__');
      final detail = await _parseRoomDetail(
        resultText,
        roomId,
        transport: transport,
      );
      if (detail == null && looksLikeChallengePage(resultText)) {
        throw const _KuaishouChallengePageException();
      }
      if (detail != null) {
        _recordEndpointSuccess('room_page', transport, sessionEpoch);
      }
      CoreLog.i(
        '[ks-request] done endpoint=room_page room=$maskedRoom '
        'status=200 hasInitState=$hasInitialState '
        'parse=${detail == null ? "failed" : "ok"} '
        'ms=${stopwatch.elapsedMilliseconds}',
      );
      return detail;
    } catch (e) {
      if (sessionEpoch != transport.epoch) {
        CoreLog.i(
          '[ks-request] drop endpoint=room_page room=$maskedRoom '
          'reason=stale_session ms=${stopwatch.elapsedMilliseconds}',
        );
        return null;
      }
      final isChallengePage = e is _KuaishouChallengePageException;
      final isCredentialInvalid = e is _KuaishouCredentialInvalidException;
      final statusCode = isCredentialInvalid
          ? 401
          : isChallengePage
              ? 403
              : e is CoreError
                  ? e.statusCode
                  : (e is DioException ? e.response?.statusCode ?? 0 : 0);
      final errorKind = e is CoreError
          ? e.kind.name
          : e is DioException
              ? e.type.name
              : e.runtimeType.toString();
      CoreLog.i(
        '[ks-request] fail endpoint=room_page room=$maskedRoom '
        'status=$statusCode kind=$errorKind '
        'ms=${stopwatch.elapsedMilliseconds}',
      );
      _classifyAndMaybeCooldown(
        statusCode,
        e,
        endpoint: 'room_page',
        transport: transport,
        sessionEpoch: sessionEpoch,
        cookieHeader: headers['cookie']?.toString() ?? '',
        isChallengePage: isChallengePage,
        isCredentialInvalid: isCredentialInvalid,
      );
      // A risk/limit response must terminate this detail attempt. Falling
      // through to an anonymous retry would turn one blocked request into a
      // burst and can also overwrite the useful status classification.
      if (isCredentialInvalid ||
          isChallengePage ||
          statusCode == 401 ||
          statusCode == 403 ||
          statusCode == 429) {
        if (e is CoreError) {
          rethrow;
        }
        throw CoreError(
          '快手房间页面请求被服务端拒绝',
          statusCode: statusCode,
          kind: CoreErrorKind.http,
          cause: e,
        );
      }
      return null;
    }
  }

  static bool looksLikeChallengePage(String html) {
    if (html.contains('window.__INITIAL_STATE__')) {
      return false;
    }
    final lower = html.toLowerCase();
    return lower.contains('captcha') ||
        lower.contains('security_verify') ||
        lower.contains('verify-center') ||
        lower.contains('verifycenter') ||
        html.contains('人机验证') ||
        html.contains('安全验证') ||
        html.contains('400010') ||
        html.contains('访问太快') ||
        html.contains('请求频繁') ||
        html.contains('访问过于频繁') ||
        html.contains('风控');
  }

  static bool looksLikeExplicitRateLimitText(String html) {
    return html.contains('400010') ||
        html.contains('访问太快') ||
        html.contains('请求过快') ||
        html.contains('请求频繁') ||
        html.contains('访问过于频繁');
  }

  void _throwIfExplicitRateLimit(dynamic response) {
    final text = response is String ? response : jsonEncode(response);
    if (!looksLikeExplicitRateLimitText(text)) return;
    throw CoreError(
      '快手访问过于频繁，请稍后重试',
      statusCode: 429,
      kind: CoreErrorKind.http,
    );
  }

  bool? _parseResponseBoolean(dynamic value) {
    if (value is bool) return value;
    if (value == 1 || value?.toString().toLowerCase() == 'true') return true;
    if (value == 0 || value?.toString().toLowerCase() == 'false') return false;
    return null;
  }

  static bool looksLikeCredentialInvalidPage(String html) {
    if (html.contains('window.__INITIAL_STATE__')) {
      return false;
    }
    final lower = html.toLowerCase();
    return html.contains('登录已失效') ||
        html.contains('登录状态已失效') ||
        html.contains('请重新登录') ||
        html.contains('账号登录状态失效') ||
        lower.contains('passport.kuaishou.com/login');
  }

  /// 根据响应分类并记录登录会话的连续拒绝证据。
  void _classifyAndMaybeCooldown(
    int statusCode,
    Object error, {
    required String endpoint,
    required _KuaishouAccountTransport transport,
    required int sessionEpoch,
    required String cookieHeader,
    bool isChallengePage = false,
    bool isCredentialInvalid = false,
  }) {
    if (isCredentialInvalid || statusCode == 401) {
      transport.lastErrorClassification =
          KuaishouErrorClassification.credentialInvalid;
      transport.hardBlocked = true;
      transport.lastHealthEvent = KuaishouAccountHealthEvent.credentialInvalid;
      _emitAccountHealthEvent(
        transport,
        KuaishouAccountHealthEvent.credentialInvalid,
      );
      return;
    }
    final immediateCooldown =
        KuaishouCooldownEvidenceTracker.immediateCooldownForStatus(statusCode);
    if (immediateCooldown != null) {
      transport.lastErrorClassification =
          KuaishouErrorClassification.rateLimited;
      transport.lastHealthEvent = null;
      return;
    }
    if (statusCode == 403) {
      transport.lastErrorClassification = isChallengePage
          ? KuaishouErrorClassification.challengePage
          : KuaishouErrorClassification.forbidden;
      transport.lastHealthEvent = null;
      return;
    }
    if (statusCode >= 400) {
      transport.lastErrorClassification = KuaishouErrorClassification.httpError;
      return;
    }
    if (error is CoreError &&
        (error.kind == CoreErrorKind.network ||
            error.kind == CoreErrorKind.http)) {
      transport.lastErrorClassification =
          KuaishouErrorClassification.networkError;
      return;
    }
    transport.lastErrorClassification = KuaishouErrorClassification.none;
  }

  void _recordEndpointSuccess(
    String endpoint,
    _KuaishouAccountTransport transport,
    int sessionEpoch,
  ) {
    if (sessionEpoch == transport.epoch) {
      transport.cooldownEvidenceTracker.recordSuccess(
        endpoint: endpoint,
        sessionEpoch: sessionEpoch,
      );
    }
  }

  void _ensureTransportAvailable(
    _KuaishouAccountTransport transport,
    KuaishouRequestSource source,
  ) {
    // Keep the original Cookie request behavior: every attempt reaches the
    // selected account. A failed primary attempt is handled by the caller's
    // secondary-account fallback instead of a host-wide or slot-wide gate.
  }

  void _emitAccountHealthEvent(
    _KuaishouAccountTransport transport,
    KuaishouAccountHealthEvent event,
  ) {
    onAccountSessionHealthEvent?.call(transport.sessionKey, event);
    onAccountHealthEvent?.call(event);
  }

  Future<LiveRoomDetail?> _parseRoomDetail(
    String resultText,
    String roomId, {
    _KuaishouAccountTransport? transport,
    bool allowDanmaku = true,
  }) async {
    try {
      final text = RegExp(
        r"window\.__INITIAL_STATE__=(.*?);",
        multiLine: false,
      ).firstMatch(resultText)?.group(1);
      if (text == null) {
        return null;
      }

      final transferData = text.replaceAll("undefined", "null");
      final jsonObj = jsonDecode(transferData);
      final liveroom = jsonObj["liveroom"];
      if (liveroom is! Map) {
        return null;
      }
      final playList = liveroom["playList"];
      if (playList is! List || playList.isEmpty) {
        return null;
      }
      final rooms = playList.whereType<Map>().toList(growable: false);
      if (rooms.isEmpty) {
        return null;
      }

      final liveState = resolvePlayListState(playList);
      var selected = rooms.first;
      if (liveState == LiveStatusState.live) {
        selected = rooms.firstWhere(
          (room) => resolveLiveState(room) == LiveStatusState.live,
        );
      }

      final liveStream = _resolveLiveStream(selected);
      final author =
          selected["author"] is Map ? selected["author"] as Map : const {};
      final gameInfo =
          selected["gameInfo"] is Map ? selected["gameInfo"] as Map : const {};
      final resolvedRoomId = author["id"]?.toString() ?? roomId;
      final liveStreamId = liveStream["id"]?.toString().trim() ?? '';
      final playUrls = liveStream["playUrls"] ?? selected["playUrls"];

      var websocketUrls = <String>[];
      void addWebsocketUrls(dynamic values) {
        if (values is! Iterable) return;
        for (final item in values) {
          final websocketUrl = item?.toString().trim() ?? '';
          if (websocketUrl.isNotEmpty &&
              !websocketUrls.contains(websocketUrl)) {
            websocketUrls.add(websocketUrl);
          }
        }
      }

      addWebsocketUrls(liveroom["websocketUrls"]);
      var danmakuToken = liveroom["token"]?.toString().trim() ?? '';
      final embeddedWebsocketInfo = selected["websocketInfo"] is Map
          ? selected["websocketInfo"] as Map
          : const {};
      if (danmakuToken.isEmpty) {
        danmakuToken = embeddedWebsocketInfo["token"]?.toString().trim() ?? '';
      }
      if (websocketUrls.isEmpty) {
        addWebsocketUrls(
          embeddedWebsocketInfo["websocketUrls"] ??
              embeddedWebsocketInfo["webSocketAddresses"],
        );
      }

      var cover = liveStream["poster"]?.toString() ??
          selected["poster"]?.toString() ??
          '';
      if (cover.isNotEmpty && !isImageUrl(cover)) {
        cover = '$cover.jpg';
      }

      KuaishouDanmakuArgs? danmakuArgs;
      if (allowDanmaku && transport != null) {
        late final KuaishouDanmakuArgs resolvedArgs;
        resolvedArgs = KuaishouDanmakuArgs(
          roomId: resolvedRoomId,
          liveStreamId: liveStreamId,
          token: danmakuToken,
          websocketUrls: websocketUrls,
          pageId: _generatePageId(),
          expTag: liveStream["expTag"]?.toString() ?? '',
          attach: selected["expTag"]?.toString() ?? '',
          cookie: _currentCookieHeaderFor(transport),
          userAgent: userAgent,
          credentialResolver: () => _resolveDanmakuCredentials(
            resolvedArgs,
            transport,
          ),
        );
        danmakuArgs = resolvedArgs;
      }

      return LiveRoomDetail(
        roomId: resolvedRoomId,
        title: resolveRoomTitle(selected),
        cover: cover,
        userName: author["name"]?.toString() ?? '',
        userAvatar: author["avatar"]?.toString() ?? '',
        online: liveState == LiveStatusState.live
            ? _parseInt(
                selected["watchingCount"] ??
                    liveStream["watchingCount"] ??
                    gameInfo["watchingCount"],
              )
            : 0,
        introduction: author["description"]?.toString(),
        notice: author["description"]?.toString(),
        status: liveState == LiveStatusState.live,
        liveStatusState: liveState,
        url: KuaishouLiveLink.publicRoomUrl(resolvedRoomId),
        data: playUrls,
        danmakuData: danmakuArgs,
        categoryId: gameInfo["id"]?.toString(),
        categoryName: gameInfo["name"]?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<_KuaishouWebsocketInfo> _getWebsocketInfoWithRetry({
    required String roomId,
    required String liveStreamId,
    required _KuaishouAccountTransport transport,
  }) async {
    return _getWebsocketInfo(
      roomId: roomId,
      liveStreamId: liveStreamId,
      transport: transport,
    ).timeout(
      const Duration(seconds: 2),
      onTimeout: _KuaishouWebsocketInfo.empty,
    );
  }

  Future<KuaishouDanmakuArgs?> _resolveDanmakuCredentials(
    KuaishouDanmakuArgs initial,
    _KuaishouAccountTransport transport,
  ) async {
    var args = initial;
    if (args.hasConnectionInfo) {
      return args;
    }

    if (args.liveStreamId.isEmpty) {
      LiveRoomDetail? freshDetail;
      try {
        freshDetail = await KuaishouRequestTrace.run(
          KuaishouRequestSource.danmakuCredential,
          () => _getRoomDetailForTransport(
            args.roomId,
            source: KuaishouRequestSource.danmakuCredential,
            transport: transport,
            requireLive: true,
          ),
        ).timeout(const Duration(seconds: 4));
      } on TimeoutException {
        return null;
      }
      final freshArgs = freshDetail.danmakuData;
      if (freshArgs is KuaishouDanmakuArgs) {
        args = freshArgs;
      }
    }
    if (args.hasConnectionInfo) {
      return args;
    }
    if (args.liveStreamId.isEmpty) {
      return null;
    }

    final info = await KuaishouRequestTrace.run(
      KuaishouRequestSource.danmakuCredential,
      () => _getWebsocketInfoWithRetry(
        roomId: args.roomId,
        liveStreamId: args.liveStreamId,
        transport: transport,
      ),
    );
    final resolved = args.copyWith(
      token: args.token.isNotEmpty ? args.token : info.token,
      websocketUrls: args.websocketUrls.isNotEmpty
          ? args.websocketUrls
          : info.websocketUrls,
    );
    return resolved.hasConnectionInfo ? resolved : null;
  }

  @override
  Future<LiveStatusState> getLiveStatusState({required String roomId}) async {
    try {
      final detail = await KuaishouRequestTrace.run(
        KuaishouRequestSource.followStatus,
        () => _getRoomDetailWithinBudget(roomId),
        scopeId: KuaishouRequestTrace.scopeId,
        forceNetwork: KuaishouRequestTrace.forceNetwork,
      );
      return detail.resolvedLiveStatus;
    } catch (_) {
      return LiveStatusState.unknown;
    }
  }

  /// Follow-list entry point. Account failover belongs to the whole batch, so
  /// this method deliberately propagates risk/auth errors to its caller.
  Future<LiveStatusState> getFollowLiveStatusState({
    required String roomId,
  }) async {
    final detail = await KuaishouRequestTrace.run(
      KuaishouRequestSource.followStatus,
      () => _getRoomDetailWithinBudget(roomId),
      scopeId: KuaishouRequestTrace.scopeId,
      forceNetwork: KuaishouRequestTrace.forceNetwork,
    );
    return detail.resolvedLiveStatus;
  }

  /// 兼容旧调用名。关注状态现已恢复为 Cookie 请求，并在主账号失败时
  /// 使用备用账号；不再建立匿名房间请求。
  Future<LiveStatusState> getAnonymousLiveStatusState({
    required String roomId,
  }) =>
      getLiveStatusState(roomId: roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    return await getLiveStatusState(roomId: roomId) == LiveStatusState.live;
  }

  // ==================== 清晰度 ====================

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    final qualities = <LivePlayQuality>[];
    final seenUrls = <String>{};

    void collect(
      dynamic value, {
      String inheritedName = '默认',
      int inheritedSort = 0,
    }) {
      if (value is String) {
        for (final url in extractPlayableUrls(value)) {
          if (seenUrls.add(url)) {
            qualities.add(
              LivePlayQuality(
                quality: inheritedName,
                sort: inheritedSort,
                data: <String>[url],
              ),
            );
          }
        }
        return;
      }
      if (value is Iterable) {
        for (final item in value) {
          collect(
            item,
            inheritedName: inheritedName,
            inheritedSort: inheritedSort,
          );
        }
        return;
      }
      if (value is! Map) {
        return;
      }

      final name = value["name"]?.toString().trim().isNotEmpty == true
          ? value["name"].toString()
          : value["shortName"]?.toString().trim().isNotEmpty == true
              ? value["shortName"].toString()
              : inheritedName;
      final level = value["level"];
      final sort = level is num
          ? level.toInt()
          : int.tryParse(level?.toString() ?? '') ?? inheritedSort;
      final directUrls = extractPlayableUrls(value["url"]);
      for (final url in directUrls) {
        if (seenUrls.add(url)) {
          qualities.add(
            LivePlayQuality(
              quality: name,
              sort: sort,
              data: <String>[url],
            ),
          );
        }
      }
      for (final entry in value.entries) {
        if (entry.key == "url") continue;
        collect(entry.value, inheritedName: name, inheritedSort: sort);
      }
    }

    final data = detail.data;
    if (data is Map && data["h264"] != null) {
      collect(data["h264"]);
      if (qualities.isEmpty) {
        collect(data);
      }
    } else {
      collect(data);
    }

    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return LivePlayUrl(urls: extractPlayableUrls(quality.data));
  }

  // ==================== Cookie 管理 ====================

  Future<String?> _getCookie(
    String url, {
    String roomId = '',
    required _KuaishouAccountTransport transport,
  }) async {
    final sessionEpoch = transport.epoch;
    final maskedRoom = _maskRoomId(roomId);
    final stopwatch = Stopwatch()..start();
    _ensureSession(transport);
    final dio = transport.sessionDio!;
    final cookieJar = transport.sessionCookieJar!;
    final requestHeaders = _headersWithCookieFor(transport);
    final requestCookieHeader = requestHeaders['cookie']?.toString() ?? '';
    try {
      final source = KuaishouRequestTrace.current;
      Future<Response<String>> request() {
        _ensureTransportAvailable(transport, source);
        return dio
            .get<String>(
              url,
              options: Options(
                headers: requestHeaders,
                responseType: ResponseType.plain,
              ),
            )
            .timeout(const Duration(seconds: 4));
      }

      final response = source == KuaishouRequestSource.followStatus
          ? await request()
          : await coordinator.schedule<Response<String>>(
              priority: _priorityForSource(source),
              key: '${transport.cacheNamespace}:http:cookie_handshake:$roomId',
              logLabel: maskedRoom,
              scopeId: KuaishouRequestTrace.scopeId,
              timeout: const Duration(seconds: 5),
              task: request,
            );
      final responseStatus = response.statusCode ?? 0;
      _throwIfExplicitRateLimit(response.data ?? '');
      if (responseStatus == 401 ||
          responseStatus == 403 ||
          responseStatus == 429) {
        // Let the catch block classify this response exactly once.
        throw CoreError(
          '快手 Cookie 握手被服务端拒绝',
          statusCode: responseStatus,
          kind: CoreErrorKind.http,
        );
      }
      if (looksLikeCredentialInvalidPage(response.data ?? '')) {
        throw const _KuaishouCredentialInvalidException();
      }
      if (looksLikeChallengePage(response.data ?? '')) {
        // A 200 challenge page is not a successful handshake. Route it
        // through the catch below so the real response contributes exactly
        // one endpoint-scoped rejection observation.
        throw const _KuaishouChallengePageException();
      }
      _ensureCurrentSession(transport, sessionEpoch);
      _recordEndpointSuccess('cookie_handshake', transport, sessionEpoch);
      List<Cookie> cookies = await cookieJar.loadForRequest(Uri.parse(url));
      if (sessionEpoch != transport.epoch) {
        CoreLog.i(
          '[ks-request] drop endpoint=cookie_handshake room=$maskedRoom '
          'reason=stale_session ms=${stopwatch.elapsedMilliseconds}',
        );
        return null;
      }
      final cookieValues = _parseCookieHeader(transport.customCookie);
      for (var i = 0; i < cookies.length; i++) {
        cookieValues[cookies[i].name] = cookies[i].value;
      }
      transport.cookieObj = cookieValues;
      transport.cookie = _formatCookieHeader(cookieValues);
      CoreLog.i(
        '[ks-request] done endpoint=cookie_handshake room=$maskedRoom '
        'status=${response.statusCode ?? 0} '
        'ms=${stopwatch.elapsedMilliseconds}',
      );
      return response.data;
    } catch (e) {
      if (sessionEpoch != transport.epoch) {
        CoreLog.i(
          '[ks-request] drop endpoint=cookie_handshake room=$maskedRoom '
          'reason=stale_session ms=${stopwatch.elapsedMilliseconds}',
        );
        return null;
      }
      final isChallengePage = e is _KuaishouChallengePageException;
      final isCredentialInvalid = e is _KuaishouCredentialInvalidException;
      final statusCode = isCredentialInvalid
          ? 401
          : isChallengePage
              ? 403
              : e is CoreError
                  ? e.statusCode
                  : (e is DioException ? e.response?.statusCode ?? 0 : 0);
      final kind = e is DioException ? e.type.name : e.runtimeType.toString();
      CoreLog.i(
        '[ks-request] fail endpoint=cookie_handshake room=$maskedRoom '
        'status=$statusCode kind=$kind ms=${stopwatch.elapsedMilliseconds}',
      );
      _classifyAndMaybeCooldown(
        statusCode,
        e,
        endpoint: 'cookie_handshake',
        transport: transport,
        sessionEpoch: sessionEpoch,
        cookieHeader: requestCookieHeader,
        isChallengePage: isChallengePage,
        isCredentialInvalid: isCredentialInvalid,
      );
      if (isCredentialInvalid ||
          isChallengePage ||
          statusCode == 401 ||
          statusCode == 403 ||
          statusCode == 429) {
        throw CoreError(
          isChallengePage ? '快手返回安全验证页面，请稍后重试' : '快手 Cookie 握手被服务端拒绝',
          statusCode: statusCode,
          kind: CoreErrorKind.http,
          cause: e,
        );
      }
      // Ordinary transport failures may fall back to the caller-provided
      // cookie, but only while this is still the current account session.
      transport.cookieObj = _parseCookieHeader(transport.customCookie);
      transport.cookie = _formatCookieHeader(transport.cookieObj);
      return null;
    }
  }

  Future<_KuaishouWebsocketInfo> _getWebsocketInfo({
    required String roomId,
    required String liveStreamId,
    required _KuaishouAccountTransport transport,
  }) {
    return coordinator.schedule(
      priority: KuaishouRequestPriority.danmakuCredential,
      key: '${transport.cacheNamespace}:websocket_info:$liveStreamId',
      logLabel: _maskRoomId(roomId),
      scopeId: KuaishouRequestTrace.scopeId,
      timeout: const Duration(seconds: 5),
      task: () {
        _ensureTransportAvailable(
          transport,
          KuaishouRequestSource.danmakuCredential,
        );
        return _fetchWebsocketInfo(
          roomId: roomId,
          liveStreamId: liveStreamId,
          transport: transport,
        );
      },
    );
  }

  Future<_KuaishouWebsocketInfo> _fetchWebsocketInfo({
    required String roomId,
    required String liveStreamId,
    required _KuaishouAccountTransport transport,
  }) async {
    final sessionEpoch = transport.epoch;
    final requestHeaders = _headersWithCookieFor(transport);
    final requestCookieHeader = requestHeaders['cookie']?.toString() ?? '';
    try {
      final kww = resolveServerKww(
        _currentCookieHeaderFor(transport),
        transport.customKww,
      );
      final result = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/liveroom/websocketinfo",
        queryParameters: {"liveStreamId": liveStreamId},
        header: {
          ...requestHeaders,
          if (kww.isNotEmpty) 'Kww': kww,
          'accept': 'application/json, text/plain, */*',
          'referer': 'https://live.kuaishou.com/u/$roomId',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
        },
        timeout: const Duration(seconds: 5),
      );
      _ensureCurrentSession(transport, sessionEpoch);
      _recordEndpointSuccess('websocket_info', transport, sessionEpoch);
      final data = result["data"];
      if (data is! Map) {
        return _KuaishouWebsocketInfo.empty();
      }
      final urls = <String>[];
      final websocketUrls = data["websocketUrls"] ??
          data["webSocketAddresses"] ??
          const <dynamic>[];
      for (final item in websocketUrls) {
        final url = item?.toString() ?? '';
        if (url.isNotEmpty) {
          urls.add(url);
        }
      }
      return _KuaishouWebsocketInfo(
        token: data["token"]?.toString() ?? '',
        websocketUrls: urls,
      );
    } catch (e) {
      if (sessionEpoch != transport.epoch) {
        throw KuaishouCooldownError('快手 Cookie 会话已重置');
      }
      final statusCode = e is CoreError
          ? e.statusCode
          : (e is DioException ? e.response?.statusCode ?? 0 : 0);
      _classifyAndMaybeCooldown(
        statusCode,
        e,
        endpoint: 'websocket_info',
        transport: transport,
        sessionEpoch: sessionEpoch,
        cookieHeader: requestCookieHeader,
      );
      if (statusCode == 403 || statusCode == 429) {
        rethrow;
      }
      return _KuaishouWebsocketInfo.empty();
    }
  }

  // ==================== DID 注册 ====================

  Future<void> _registerDid({
    required _KuaishouAccountTransport transport,
    required int sessionEpoch,
    String? categoryId,
    String? categoryName,
  }) async {
    if (sessionEpoch != transport.epoch) return;
    var did = transport.cookieObj['did'];
    if (did == null || did.isEmpty) return;
    if (transport.didReportAttempted) return;
    transport.didReportAttempted = true;
    if (sessionEpoch != transport.epoch) return;
    try {
      await coordinator.schedule<void>(
        priority: KuaishouRequestPriority.did,
        key: '${transport.cacheNamespace}:did_register',
        logLabel: 'did',
        scopeId: 'kuaishou:did',
        task: () async {
          _ensureTransportAvailable(transport, KuaishouRequestSource.userEnter);
          final stopwatch = Stopwatch()..start();
          await HttpClient.instance.postJson(
            'https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC',
            header: _headers,
            data: _buildMisc2Data(
              did,
              categoryId: categoryId,
              categoryName: categoryName,
            ),
          );
          CoreLog.i(
            '[ks-request] done endpoint=did_register '
            'ms=${stopwatch.elapsedMilliseconds}',
          );
        },
      );
      if (sessionEpoch != transport.epoch) return;
    } catch (_) {
      CoreLog.i('[ks-request] fail endpoint=did_register');
    }
  }

  Map<String, dynamic> _buildMisc2Data(
    String did, {
    String? categoryId,
    String? categoryName,
  }) {
    return {
      'common': {
        'identity_package': {'device_id': did, 'global_id': ''},
        'app_package': {
          'language': 'zh-CN',
          'platform': 10,
          'container': 'WEB',
          'product_name': 'KS_GAME_LIVE_PC',
        },
        'device_package': {
          'os_version': 'NT 10.0',
          'model': 'Windows',
          'ua':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        'need_encrypt': 'false',
        'network_package': {'type': 3},
        'h5_extra_attr':
            '{"sdk_name":"webLogger","sdk_version":"3.9.49","sdk_bundle":"log.common.js","app_version_name":"","host_product":"","resolution":"1920x1080","screen_with":1920,"screen_height":1080,"device_pixel_ratio":1,"domain":"https://live.kuaishou.com"}',
        'global_attr': '{}',
      },
      'logs': [
        {
          'client_timestamp': DateTime.now().millisecondsSinceEpoch,
          'client_increment_id': math.Random().nextInt(8999) + 1000,
          'session_id': _generateSessionId(),
          'time_zone': 'GMT+08:00',
          'event_package': {
            'task_event': {
              'type': 1,
              'status': 0,
              'operation_type': 1,
              'operation_direction': 0,
              'session_id': _generateSessionId(),
              'url_package': {
                'page': 'GAME_DETAL_PAGE',
                'identity': _generateUuid(),
                'page_type': 2,
                'params': jsonEncode({
                  'game_id': categoryId ?? '',
                  'game_name': categoryName ?? '',
                }),
              },
              'element_package': {},
            },
          },
        },
      ],
    };
  }

  String _generateSessionId() {
    return '${_hex(8)}-${_hex(4)}-${_hex(4)}-${_hex(4)}-${_hex(12)}';
  }

  String _generateUuid() {
    return '${_hex(8)}-${_hex(4)}-${_hex(4)}-${_hex(4)}-${_hex(12)}';
  }

  String _generatePageId() {
    const chars =
        'useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict';
    final random = math.Random();
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String _hex(int length) {
    const chars = '0123456789abcdef';
    var result = '';
    for (var i = 0; i < length; i++) {
      result += chars[math.Random().nextInt(16)];
    }
    return result;
  }

  // ==================== 工具方法 ====================

  static bool isImageUrl(String url) {
    if (url.isEmpty) return false;
    final lastSegment = url.split('?').first.split('/').last;
    // 无扩展名的 http(s) URL（如快手 live3.static.yximgs.com 实时截图
    // "...~1785822457911~1"）是有效的动态图片，直接可用；
    // 若按"无扩展名"处理会拼出 404 的 .jpg，封面失效。
    if (!lastSegment.contains('.')) {
      return true;
    }
    var ext = lastSegment.split('.').last.toLowerCase();
    return _imageExtensions.contains(ext);
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  String _currentCookieHeaderFor(_KuaishouAccountTransport transport) {
    return transport.customCookie.isNotEmpty
        ? _mergeCookie(transport.customCookie, transport.cookie)
        : transport.cookie;
  }

  String _mergeCookie(String baseCookie, String extraCookie) {
    final values = _parseCookieHeader(baseCookie);
    values.addAll(_parseCookieHeader(extraCookie));
    return _formatCookieHeader(values);
  }

  Map<String, String> _parseCookieHeader(String cookie) {
    final result = <String, String>{};
    for (final part in cookie.split(';')) {
      final item = part.trim();
      if (item.isEmpty) {
        continue;
      }
      final index = item.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final key = item.substring(0, index).trim();
      final value = item.substring(index + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  String _formatCookieHeader(Map<String, String> values) {
    return values.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

class _KuaishouWebsocketInfo {
  final String token;
  final List<String> websocketUrls;

  _KuaishouWebsocketInfo({required this.token, required this.websocketUrls});

  factory _KuaishouWebsocketInfo.empty() {
    return _KuaishouWebsocketInfo(token: '', websocketUrls: <String>[]);
  }
}

class _KuaishouSubCategoryPage {
  const _KuaishouSubCategoryPage({
    required this.items,
    required this.hasMore,
  });

  final List<LiveSubCategory> items;
  final bool hasMore;
}

class _KuaishouCategorySnapshot {
  const _KuaishouCategorySnapshot(this.savedAt, this.categories);

  final DateTime savedAt;
  final List<LiveCategory> categories;
}

class _KuaishouChallengePageException implements Exception {
  const _KuaishouChallengePageException();
}

class _KuaishouCredentialInvalidException implements Exception {
  const _KuaishouCredentialInvalidException();
}

class _KuaishouAccountTransport {
  _KuaishouAccountTransport(this.sessionKey);

  final String sessionKey;
  String customCookie = '';
  String customKww = '';
  String cookie = '';
  Map<String, String> cookieObj = {};
  Dio? sessionDio;
  CookieJar? sessionCookieJar;
  int epoch = 0;
  bool didReportAttempted = false;
  bool hardBlocked = false;
  DateTime? cooldownUntil;
  KuaishouErrorClassification lastErrorClassification =
      KuaishouErrorClassification.none;
  KuaishouAccountHealthEvent? lastHealthEvent;
  final KuaishouCooldownEvidenceTracker cooldownEvidenceTracker =
      KuaishouCooldownEvidenceTracker();

  String get cacheNamespace => 'account:$sessionKey:$epoch';

  void resetCredential({required String cookie, required String kww}) {
    epoch += 1;
    customCookie = cookie;
    customKww = kww;
    this.cookie = '';
    cookieObj = {};
    sessionDio = null;
    sessionCookieJar = null;
    didReportAttempted = false;
    hardBlocked = false;
    cooldownUntil = null;
    lastErrorClassification = KuaishouErrorClassification.none;
    lastHealthEvent = null;
    cooldownEvidenceTracker.reset();
  }
}
