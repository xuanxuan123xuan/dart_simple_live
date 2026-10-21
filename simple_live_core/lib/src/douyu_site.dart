import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/common/core_cancellation.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/douyu_cookie_helper.dart';
import 'package:simple_live_core/src/danmaku/douyu_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_contribution_rank.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:html_unescape/html_unescape.dart';

class _DouyuPlayUrlAttempt {
  const _DouyuPlayUrlAttempt.success(
      this.url, this.actualQuality, this.rateOrder)
      : error = null,
        stackTrace = null;

  const _DouyuPlayUrlAttempt.failure(this.error, this.stackTrace)
      : url = '',
        actualQuality = null,
        rateOrder = const [];

  final String url;
  final LivePlayQuality? actualQuality;
  final List<int> rateOrder;
  final Object? error;
  final StackTrace? stackTrace;
}

/// The result of checking whether the current Douyu cookie needs renewal.
enum DouyuCookieRefreshResult {
  unchanged,
  refreshed,
  missingCredentials,
  failed,
  deferred,
}

class _DouyuCookieRefreshOutcome {
  const _DouyuCookieRefreshOutcome(this.generation, this.result);

  final int generation;
  final DouyuCookieRefreshResult result;
}

class _DouyuEncryptionKey {
  const _DouyuEncryptionKey({
    required this.key,
    required this.randStr,
    required this.encTime,
    required this.isSpecial,
    required this.encData,
    required this.expiresAt,
  });

  final String key;
  final String randStr;
  final int encTime;
  final bool isSpecial;
  final String encData;
  final DateTime expiresAt;
}

class _DouyuRateGroup {
  const _DouyuRateGroup(this.rate, this.name);

  final int rate;
  final String name;
}

class _DouyuRoomStatus {
  const _DouyuRoomStatus({
    required this.state,
    required this.isRecord,
    required this.isLiveStream,
  });

  final LiveStatusState state;
  final bool isRecord;
  final bool isLiveStream;
}

class DouyuSite implements LiveSite {
  static const String _defaultDid = '10000000000000000000000000001501';
  static const String _origin = 'https://www.douyu.com';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43';
  static const Duration _encryptionCacheTtl = Duration(minutes: 5);
  static const int _maxEncryptionEncTime = 4096;
  static const Duration _authRefreshCooldown = Duration(seconds: 60);

  DouyuSite({
    DateTime Function()? clock,
    this.onCookieRefreshed,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Called after a refreshed cookie has been accepted and stored in memory.
  Future<void> Function(String cookie)? onCookieRefreshed;

  String _cookie = '';
  int _sessionGeneration = 0;
  _DouyuEncryptionKey? _cachedEncryptionKey;
  int? _cachedEncryptionGeneration;
  Future<_DouyuEncryptionKey>? _encryptionKeyRequest;
  int? _encryptionRequestGeneration;
  Future<_DouyuCookieRefreshOutcome>? _authRefreshRequest;
  int? _authRefreshFailedGeneration;
  DateTime? _authRefreshFailedUntil;
  int _activePlaybackOperations = 0;

  /// Optional authenticated web cookie. Empty preserves anonymous behavior.
  String get cookie => _cookie;

  set cookie(String value) {
    final normalized = DouyuCookieHelper.normalizeInput(value);
    if (normalized == _cookie) return;
    _cookie = normalized;
    _advanceSession();
  }

  void _advanceSession({bool preserveAuthRefresh = false}) {
    _sessionGeneration++;
    _cachedEncryptionKey = null;
    _cachedEncryptionGeneration = null;
    _encryptionKeyRequest = null;
    _encryptionRequestGeneration = null;
    if (!preserveAuthRefresh) {
      _authRefreshRequest = null;
    }
    _authRefreshFailedGeneration = null;
    _authRefreshFailedUntil = null;
  }

  void _assertSession(int generation) {
    if (generation != _sessionGeneration) {
      throw CoreCancelledError(
        cause: StateError('斗鱼登录态已改变，取消旧会话请求'),
      );
    }
  }

  String _requestCookie(String cookieSnapshot) {
    if (cookieSnapshot.trim().isEmpty) {
      return 'dy_did=$_defaultDid; acf_did=$_defaultDid';
    }
    final parsed = DouyuCookieHelper.parse(cookieSnapshot);
    final hasDid = parsed.keys.any((key) =>
        key.toLowerCase() == 'dy_did' || key.toLowerCase() == 'acf_did');
    if (hasDid) return cookieSnapshot;
    return '$cookieSnapshot; dy_did=$_defaultDid; acf_did=$_defaultDid';
  }

  String _didForCookie(String cookieSnapshot) {
    final parsed = DouyuCookieHelper.parse(cookieSnapshot);
    String valueFor(String name) {
      for (final entry in parsed.entries) {
        if (entry.key.toLowerCase() == name) return entry.value.trim();
      }
      return '';
    }

    return valueFor('dy_did').isNotEmpty
        ? valueFor('dy_did')
        : valueFor('acf_did').isNotEmpty
            ? valueFor('acf_did')
            : _defaultDid;
  }

  Map<String, dynamic> _douyuHeaders(
    String roomId, {
    String? cookieSnapshot,
  }) =>
      {
        'Origin': _origin,
        'Referer': '$_origin/$roomId',
        'User-Agent': _userAgent,
        'Cookie': _requestCookie(cookieSnapshot ?? _cookie),
      };

  Map<String, dynamic> _roomHeaders(String roomId) => _douyuHeaders(roomId);

  @override
  Future<LiveStatusState> getLiveStatusState({required String roomId}) async {
    final roomInfo = await _getRoomInfo(roomId);
    return _parseRoomStatus(roomInfo).state;
  }

  @override
  String id = "douyu";

  @override
  String name = "斗鱼直播";

  @override
  LiveDanmaku getDanmaku() => DouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getJson(
      "https://m.douyu.com/api/cate/list",
    );
    var subCateList = result["data"]["cate2Info"] as List;
    for (var item in result["data"]["cate1Info"]) {
      var cate1Id = item["cate1Id"];
      var cate1Name = item["cate1Name"];
      List<LiveSubCategory> subCategories = [];
      subCateList.where((x) => x["cate1Id"] == cate1Id).forEach((element) {
        subCategories.add(
          LiveSubCategory(
            pic: element["icon"],
            id: element["cate2Id"].toString(),
            parentId: cate1Id.toString(),
            name: element["cate2Name"].toString(),
          ),
        );
      });
      categories.add(
        LiveCategory(
          id: cate1Id.toString(),
          name: cate1Name.toString(),
          children: subCategories,
        ),
      );
    }
    // 根据ID排序
    categories.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) =>
      _trackPlaybackOperation(() async {
        final generation = await _preparePlaybackSession();
        _assertSession(generation);
        final cookieSnapshot = _cookie;
        final did = _didForCookie(cookieSnapshot);
        final encryption = await _getEncryptionKey(
          detail.roomId,
          did: did,
          cookieSnapshot: cookieSnapshot,
          generation: generation,
        );
        final result = await _requestH5Play(
          roomId: detail.roomId,
          rate: -1,
          cdn: '',
          did: did,
          cookieSnapshot: cookieSnapshot,
          generation: generation,
          encryption: encryption,
        );
        _assertSession(generation);

        final cdns = _readCdnList(result['cdnsWithName']);
        final rateGroups = _readRateGroups(result['multirates']);
        return rateGroups
            .map(
              (group) => LivePlayQuality(
                quality: group.name,
                data: DouyuPlayData(
                  group.rate,
                  cdns,
                  rateOrder: rateGroups.map((item) => item.rate).toList(),
                  rateNames: {
                    for (final item in rateGroups) item.rate: item.name
                  },
                ),
              ),
            )
            .toList(growable: false);
      });

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) =>
      _trackPlaybackOperation(() async {
        final generation = await _preparePlaybackSession();
        _assertSession(generation);
        final cookieSnapshot = _cookie;
        final did = _didForCookie(cookieSnapshot);
        final data = quality.data as DouyuPlayData;
        final encryption = await _getEncryptionKey(
          detail.roomId,
          did: did,
          cookieSnapshot: cookieSnapshot,
          generation: generation,
        );

        // CDN 请求并发执行；Future.wait 保留线路原有顺序。
        final attempts = await Future.wait(
          data.cdns.map(
            (cdn) => _getPlayUrlForCdn(
              roomId: detail.roomId,
              cdn: cdn,
              requestedQuality: quality,
              requestedRate: data.rate,
              did: did,
              cookieSnapshot: cookieSnapshot,
              generation: generation,
              encryption: encryption,
            ),
          ),
        );
        _assertSession(generation);
        final playable =
            attempts.where((attempt) => attempt.url.isNotEmpty).toList();
        if (playable.isEmpty) {
          for (final attempt in attempts) {
            final error = attempt.error;
            final stackTrace = attempt.stackTrace;
            if (error != null && stackTrace != null) {
              Error.throwWithStackTrace(error, stackTrace);
            }
          }
        }
        final selected = _selectActualQuality(playable, data);
        final urls = playable
            .where((attempt) => _sameQuality(attempt.actualQuality, selected))
            .map((attempt) => attempt.url)
            .toList();
        final actualQuality = selected;
        return LivePlayUrl(urls: urls, actualQuality: actualQuality);
      });

  Future<String> getPlayUrl(
    String roomId,
    String args,
    int rate,
    String cdn,
  ) =>
      _trackPlaybackOperation(() async {
        // Kept as a public compatibility method; current signing uses the cached
        // encryption key and does not consume expired room-detail script data.
        final generation = await _preparePlaybackSession();
        _assertSession(generation);
        final cookieSnapshot = _cookie;
        final did = _didForCookie(cookieSnapshot);
        final encryption = await _getEncryptionKey(
          roomId,
          did: did,
          cookieSnapshot: cookieSnapshot,
          generation: generation,
        );
        final result = await _requestH5Play(
          roomId: roomId,
          rate: rate,
          cdn: cdn,
          did: did,
          cookieSnapshot: cookieSnapshot,
          generation: generation,
          encryption: encryption,
        );
        _assertSession(generation);
        final url = _readStreamUrl(result);
        if (url == null) {
          throw CoreError('斗鱼取流响应缺少可播放地址', kind: CoreErrorKind.response);
        }
        return url;
      });

  Future<T> _trackPlaybackOperation<T>(Future<T> Function() operation) async {
    _activePlaybackOperations++;
    try {
      return await operation();
    } finally {
      _activePlaybackOperations--;
    }
  }

  Future<int> _preparePlaybackSession() async {
    final generation = _sessionGeneration;
    final pending = _authRefreshRequest;
    if (pending != null) {
      final outcome = await pending;
      _assertSession(outcome.generation);
      return outcome.generation;
    }

    if (!DouyuCookieHelper.needsRefresh(_cookie, _clock())) {
      _assertSession(generation);
      return generation;
    }
    final outcome = await _refreshCookieIfNeeded();
    _assertSession(outcome.generation);
    return outcome.generation;
  }

  /// Renews an expired cookie, or one expiring within [refreshAhead].
  ///
  /// A proactive check waits for an existing renewal, but defers starting a
  /// new one while a playback request is using the current session.
  Future<DouyuCookieRefreshResult> refreshCookieIfNeeded({
    Duration refreshAhead = Duration.zero,
    bool proactive = false,
  }) async =>
      (await _refreshCookieIfNeeded(
        refreshAhead: refreshAhead,
        proactive: proactive,
      ))
          .result;

  Future<_DouyuCookieRefreshOutcome> _refreshCookieIfNeeded({
    Duration refreshAhead = Duration.zero,
    bool proactive = false,
  }) async {
    final generation = _sessionGeneration;
    final cookieSnapshot = _cookie;
    if (cookieSnapshot.trim().isEmpty) {
      return _DouyuCookieRefreshOutcome(
        generation,
        DouyuCookieRefreshResult.unchanged,
      );
    }

    final pending = _authRefreshRequest;
    if (pending != null) {
      return pending;
    }

    final expiry = DouyuCookieHelper.jwtExpiresAt(cookieSnapshot);
    if (expiry != null && expiry.isAfter(_clock().add(refreshAhead))) {
      return _DouyuCookieRefreshOutcome(
        generation,
        DouyuCookieRefreshResult.unchanged,
      );
    }

    if (_authRefreshFailedGeneration == generation &&
        _authRefreshFailedUntil != null &&
        _clock().isBefore(_authRefreshFailedUntil!)) {
      return _DouyuCookieRefreshOutcome(
        generation,
        DouyuCookieRefreshResult.failed,
      );
    }

    final cookieFields = DouyuCookieHelper.parse(cookieSnapshot);
    String field(String name) {
      for (final entry in cookieFields.entries) {
        if (entry.key.toLowerCase() == name) return entry.value.trim();
      }
      return '';
    }

    final did = field('dy_did').isNotEmpty ? field('dy_did') : field('acf_did');
    final ltp0 = field('ltp0');
    if (did.isEmpty || ltp0.isEmpty) {
      return _DouyuCookieRefreshOutcome(
        generation,
        DouyuCookieRefreshResult.missingCredentials,
      );
    }

    if (proactive && _activePlaybackOperations > 0) {
      return _DouyuCookieRefreshOutcome(
        generation,
        DouyuCookieRefreshResult.deferred,
      );
    }

    final future = _refreshCookie(
      generation: generation,
      cookieSnapshot: cookieSnapshot,
      did: did,
      ltp0: ltp0,
    );
    _authRefreshRequest = future;
    try {
      return await future;
    } finally {
      if (identical(_authRefreshRequest, future)) {
        _authRefreshRequest = null;
      }
    }
  }

  Future<_DouyuCookieRefreshOutcome> _refreshCookie({
    required int generation,
    required String cookieSnapshot,
    required String did,
    required String ltp0,
  }) async {
    try {
      final timestamp = _clock().millisecondsSinceEpoch.toString();
      final response = await HttpClient.instance.dio.get<dynamic>(
        'https://passport.douyu.com/lapi/passport/iframe/safeAuth',
        queryParameters: {
          'client_id': '1',
          't': timestamp,
          '_': timestamp,
          'callback': 'axiosJsonpCallback',
        },
        options: Options(
          headers: _douyuHeaders(
            '',
            cookieSnapshot: 'dy_did=$did; LTP0=$ltp0',
          ),
          extra: const {'redactResponse': true},
        ),
      );
      _assertSession(generation);

      final setCookies = response.headers['set-cookie'] ?? const <String>[];
      if (!_setCookieHasJwt(setCookies)) {
        throw const FormatException('safeAuth 未返回 JWT Cookie');
      }
      final refreshedCookie = DouyuCookieHelper.mergeSetCookie(
        cookieSnapshot,
        setCookies,
        _clock(),
      );
      final jwtExpiry = DouyuCookieHelper.jwtExpiresAt(refreshedCookie);
      if (jwtExpiry == null || !jwtExpiry.isAfter(_clock())) {
        throw const FormatException('safeAuth 未返回仍有效的 JWT');
      }

      _cookie = DouyuCookieHelper.normalizeInput(refreshedCookie);
      _advanceSession(preserveAuthRefresh: true);
      final refreshedGeneration = _sessionGeneration;
      try {
        await onCookieRefreshed?.call(_cookie);
      } catch (_) {
        // Playback remains usable when persistence reports an error. The
        // account callback still receives the refreshed in-memory value.
      }
      _assertSession(refreshedGeneration);
      return _DouyuCookieRefreshOutcome(
        refreshedGeneration,
        DouyuCookieRefreshResult.refreshed,
      );
    } catch (error) {
      if (generation != _sessionGeneration) {
        throw CoreCancelledError(cause: error);
      }
      _authRefreshFailedGeneration = generation;
      _authRefreshFailedUntil = _clock().add(_authRefreshCooldown);
      return _DouyuCookieRefreshOutcome(
        generation,
        DouyuCookieRefreshResult.failed,
      );
    }
  }

  bool _setCookieHasJwt(List<String> setCookies) {
    for (final header in setCookies) {
      final cookiePair = header.split(';').first.trim();
      final separator = cookiePair.indexOf('=');
      if (separator > 0 &&
          cookiePair.substring(0, separator).trim().toLowerCase() ==
              'acf_jwt_token') {
        return true;
      }
    }
    return false;
  }

  Future<_DouyuEncryptionKey> _getEncryptionKey(
    String roomId, {
    required String did,
    required String cookieSnapshot,
    required int generation,
  }) async {
    _assertSession(generation);
    final cached = _cachedEncryptionKey;
    if (_cachedEncryptionGeneration == generation &&
        cached != null &&
        _clock().isBefore(cached.expiresAt)) {
      return cached;
    }

    final pending = _encryptionKeyRequest;
    if (pending != null && _encryptionRequestGeneration == generation) {
      return pending;
    }

    final future = _loadEncryptionKey(
      roomId,
      did: did,
      cookieSnapshot: cookieSnapshot,
      generation: generation,
    );
    _encryptionKeyRequest = future;
    _encryptionRequestGeneration = generation;
    try {
      return await future;
    } finally {
      if (identical(_encryptionKeyRequest, future)) {
        _encryptionKeyRequest = null;
        _encryptionRequestGeneration = null;
      }
    }
  }

  Future<_DouyuEncryptionKey> _loadEncryptionKey(
    String roomId, {
    required String did,
    required String cookieSnapshot,
    required int generation,
  }) async {
    final response = await HttpClient.instance.getJson(
      '$_origin/wgapi/livenc/liveweb/websec/getEncryption',
      queryParameters: {'did': did},
      header: _douyuHeaders(roomId, cookieSnapshot: cookieSnapshot),
      redactResponse: true,
    );
    _assertSession(generation);
    if (response is! Map) {
      throw CoreError('斗鱼加密参数响应格式错误', kind: CoreErrorKind.response);
    }
    if (_asInt(response['error']) != 0) {
      throw CoreError('斗鱼加密参数请求失败', kind: CoreErrorKind.response);
    }
    if (response['data'] is! Map) {
      throw CoreError('斗鱼加密参数响应格式错误', kind: CoreErrorKind.response);
    }
    final data = response['data'] as Map;
    final key = data['key']?.toString() ?? '';
    final randStr = data['rand_str']?.toString() ?? '';
    final encData = data['enc_data']?.toString() ?? '';
    final encTime = int.tryParse(data['enc_time']?.toString() ?? '');
    final expireAt = int.tryParse(data['expire_at']?.toString() ?? '');
    if (key.isEmpty ||
        randStr.isEmpty ||
        encData.isEmpty ||
        encTime == null ||
        encTime < 1 ||
        encTime > _maxEncryptionEncTime ||
        expireAt == null ||
        expireAt <= 0 ||
        expireAt > 8640000000000) {
      throw CoreError('斗鱼加密参数缺失', kind: CoreErrorKind.response);
    }

    final now = _clock();
    final serverExpiry = DateTime.fromMillisecondsSinceEpoch(expireAt * 1000);
    final localExpiry = now.add(_encryptionCacheTtl);
    final expiresAt =
        serverExpiry.isBefore(localExpiry) ? serverExpiry : localExpiry;
    if (!expiresAt.isAfter(now)) {
      throw CoreError('斗鱼加密参数已过期', kind: CoreErrorKind.response);
    }
    final encryption = _DouyuEncryptionKey(
      key: key,
      randStr: randStr,
      encTime: encTime,
      isSpecial: _asInt(data['is_special']) == 1,
      encData: encData,
      expiresAt: expiresAt,
    );
    _assertSession(generation);
    _cachedEncryptionKey = encryption;
    _cachedEncryptionGeneration = generation;
    return encryption;
  }

  String _signedBody({
    required String roomId,
    required String did,
    required int rate,
    required String cdn,
    required _DouyuEncryptionKey encryption,
  }) {
    final timestamp = (_clock().millisecondsSinceEpoch ~/ 1000).toString();
    var secret = encryption.randStr;
    for (var i = 0; i < encryption.encTime; i++) {
      secret = md5.convert(utf8.encode('$secret${encryption.key}')).toString();
    }
    final salt = encryption.isSpecial ? '' : '$roomId$timestamp';
    final auth =
        md5.convert(utf8.encode('$secret${encryption.key}$salt')).toString();
    return Uri(
      queryParameters: {
        'enc_data': encryption.encData,
        'tt': timestamp,
        'did': did,
        'auth': auth,
        'cdn': cdn,
        'ver': 'Douyu_new',
        'rate': '$rate',
        'hevc': '0',
        'ive': '0',
        'fa': '0',
      },
    ).query;
  }

  Future<Map> _requestH5Play({
    required String roomId,
    required int rate,
    required String cdn,
    required String did,
    required String cookieSnapshot,
    required int generation,
    required _DouyuEncryptionKey encryption,
  }) async {
    final body = _signedBody(
      roomId: roomId,
      did: did,
      rate: rate,
      cdn: cdn,
      encryption: encryption,
    );
    final response = await HttpClient.instance.postJson(
      '$_origin/lapi/live/getH5PlayV1/$roomId',
      data: body,
      header: _douyuHeaders(roomId, cookieSnapshot: cookieSnapshot),
      formUrlEncoded: true,
    );
    _assertSession(generation);
    if (response is! Map) {
      throw CoreError('斗鱼取流响应格式错误', kind: CoreErrorKind.response);
    }
    if (_asInt(response['error']) != 0) {
      throw CoreError('斗鱼取流请求失败', kind: CoreErrorKind.response);
    }
    if (response['data'] is! Map) {
      throw CoreError('斗鱼取流响应格式错误', kind: CoreErrorKind.response);
    }
    return response['data'] as Map;
  }

  Future<_DouyuPlayUrlAttempt> _getPlayUrlForCdn({
    required String roomId,
    required String cdn,
    required LivePlayQuality requestedQuality,
    required int requestedRate,
    required String did,
    required String cookieSnapshot,
    required int generation,
    required _DouyuEncryptionKey encryption,
  }) async {
    try {
      final response = await _requestH5Play(
        roomId: roomId,
        rate: requestedRate,
        cdn: cdn,
        did: did,
        cookieSnapshot: cookieSnapshot,
        generation: generation,
        encryption: encryption,
      );
      final url = _readStreamUrl(response);
      if (url == null) {
        throw CoreError('斗鱼取流响应缺少可播放地址', kind: CoreErrorKind.response);
      }
      final groups = _readRateGroups(response['multirates']);
      final rateOrder =
          groups.map((group) => group.rate).toList(growable: false);
      final actualRate = _asInt(response['rate']);
      final group = actualRate == null
          ? null
          : _findRateGroup(groups, actualRate) ??
              _groupFromRequestedData(requestedQuality, actualRate);
      return _DouyuPlayUrlAttempt.success(
        url,
        group == null
            ? _unknownQuality()
            : _qualityForGroup(group, requestedQuality.data),
        rateOrder,
      );
    } catch (error, stackTrace) {
      return _DouyuPlayUrlAttempt.failure(error, stackTrace);
    }
  }

  _DouyuRateGroup? _groupFromRequestedData(
    LivePlayQuality requestedQuality,
    int rate,
  ) {
    final data = requestedQuality.data;
    if (data is! DouyuPlayData) return null;
    final name = data.rateNames[rate] ??
        (data.rate == rate ? requestedQuality.quality : null);
    return name == null || name.isEmpty ? null : _DouyuRateGroup(rate, name);
  }

  _DouyuRateGroup? _findRateGroup(List<_DouyuRateGroup> groups, int rate) {
    for (final group in groups) {
      if (group.rate == rate) return group;
    }
    return null;
  }

  LivePlayQuality _qualityForGroup(
      _DouyuRateGroup group, dynamic requestedData) {
    final data = requestedData is DouyuPlayData ? requestedData : null;
    return LivePlayQuality(
      quality: group.name,
      data: DouyuPlayData(
        group.rate,
        data?.cdns ?? const <String>[],
        rateOrder: data?.rateOrder ?? const [],
        rateNames: data?.rateNames ?? const {},
      ),
    );
  }

  LivePlayQuality _unknownQuality() =>
      LivePlayQuality(quality: '清晰度未确认', data: null);

  LivePlayQuality _selectActualQuality(
    List<_DouyuPlayUrlAttempt> playable,
    DouyuPlayData requestedData,
  ) {
    final byRate = <int, LivePlayQuality>{};
    for (final attempt in playable) {
      final quality = attempt.actualQuality;
      final data = quality?.data;
      if (quality != null && data is DouyuPlayData) {
        byRate.putIfAbsent(data.rate, () => quality);
      }
    }
    if (byRate.containsKey(requestedData.rate)) {
      return byRate[requestedData.rate]!;
    }
    final order = requestedData.rateOrder.isNotEmpty
        ? requestedData.rateOrder
        : playable.expand((attempt) => attempt.rateOrder).toList();
    for (final rate in order) {
      final quality = byRate[rate];
      if (quality != null) return quality;
    }
    if (byRate.isNotEmpty) return byRate.values.first;
    return _unknownQuality();
  }

  bool _sameQuality(LivePlayQuality? quality, LivePlayQuality selected) {
    final actualData = quality?.data;
    final selectedData = selected.data;
    if (actualData is DouyuPlayData && selectedData is DouyuPlayData) {
      return actualData.rate == selectedData.rate;
    }
    return actualData == null && selectedData == null;
  }

  int? _asInt(dynamic value) => value is int ? value : int.tryParse('$value');

  List<_DouyuRateGroup> _readRateGroups(dynamic value) {
    if (value is! List) return const [];
    final groups = <_DouyuRateGroup>[];
    for (final item in value) {
      if (item is! Map) continue;
      final rate = _asInt(item['rate']);
      final name = item['name']?.toString().trim() ?? '';
      if (rate == null || name.isEmpty) continue;
      groups.add(_DouyuRateGroup(rate, name));
    }
    return groups;
  }

  List<String> _readCdnList(dynamic value) {
    if (value is! List) return const [];
    final cdns = <String>[];
    for (final item in value) {
      if (item is! Map) continue;
      final cdn = item['cdn']?.toString().trim() ?? '';
      if (cdn.isNotEmpty) cdns.add(cdn);
    }
    // scdn 常作为备用线路，放到稳定顺序的末尾。
    final preferred = cdns.where((cdn) => !cdn.startsWith('scdn'));
    final secondary = cdns.where((cdn) => cdn.startsWith('scdn'));
    return [...preferred, ...secondary];
  }

  String? _readStreamUrl(Map data) {
    final baseUrl = data['rtmp_url']?.toString().trim() ?? '';
    final streamName =
        HtmlUnescape().convert(data['rtmp_live']?.toString() ?? '').trim();
    if (baseUrl.isEmpty || streamName.isEmpty) return null;
    return '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$streamName';
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/weblist/apinc/allpage/6/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final roomInfo = await _getRoomInfo(roomId);
    final canonicalRoomId = roomInfo["room_id"].toString().trim();
    final roomStatus = _parseRoomStatus(roomInfo);
    final roomBizAll = roomInfo["room_biz_all"];
    if (roomBizAll is! Map) {
      throw CoreError("斗鱼房间详情响应格式错误", kind: CoreErrorKind.response);
    }

    final h5RoomInfo = await HttpClient.instance.getJson(
      "https://www.douyu.com/swf_api/h5room/$canonicalRoomId",
      queryParameters: {},
      header: _roomHeaders(canonicalRoomId),
    );
    if (h5RoomInfo is! Map ||
        (h5RoomInfo["data"] != null && h5RoomInfo["data"] is! Map)) {
      throw CoreError("斗鱼房间详情响应格式错误", kind: CoreErrorKind.response);
    }
    final h5Data = h5RoomInfo["data"] as Map?;
    final showTime = h5Data?["show_time"]?.toString();

    return LiveRoomDetail(
      cover: roomInfo["room_pic"].toString(),
      online: int.tryParse(roomBizAll["hot"].toString()) ?? 0,
      roomId: canonicalRoomId,
      title: roomInfo["room_name"].toString(),
      userName: roomInfo["owner_name"].toString(),
      userAvatar: roomInfo["owner_avatar"].toString(),
      introduction: roomInfo["show_details"].toString(),
      notice: "",
      status: roomStatus.isLiveStream,
      liveStatusState: roomStatus.state,
      danmakuData: canonicalRoomId,
      data: "",
      url: "https://www.douyu.com/$roomId",
      isRecord: roomStatus.isRecord,
      showTime: showTime,
      categoryId: roomInfo["cate2Id"]?.toString() ??
          roomInfo["cate_id"]?.toString() ??
          roomInfo["cid1"]?.toString(),
      categoryName: roomInfo["cate2Name"]?.toString() ??
          roomInfo["game_name"]?.toString() ??
          roomInfo["cate_name"]?.toString(),
      categoryParentId:
          roomInfo["cate1Id"]?.toString() ?? roomInfo["cid2"]?.toString(),
      categoryParentName: roomInfo["cate1Name"]?.toString() ??
          roomInfo["parent_cate_name"]?.toString(),
      categoryPic: roomInfo["game_icon"]?.toString() ??
          roomInfo["game_icon_url"]?.toString(),
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchShow",
      queryParameters: {"kw": keyword, "page": page, "pageSize": 20},
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
      cancellation: cancellation,
    );
    try {
      if (result is! Map) {
        throw CoreError("斗鱼搜索房间响应格式错误", kind: CoreErrorKind.response);
      }
      if (result['error'] != 0) {
        throw CoreError(
          result['msg']?.toString() ?? '斗鱼直播间搜索失败',
          kind: CoreErrorKind.search,
        );
      }
      final data = result['data'];
      final rawItems = data is Map ? data['relateShow'] : null;
      if (rawItems is! List) {
        throw CoreError("斗鱼搜索房间响应格式错误", kind: CoreErrorKind.response);
      }
      var items = <LiveRoomItem>[];
      for (var item in rawItems) {
        if (item is! Map) {
          throw CoreError("斗鱼搜索房间响应格式错误", kind: CoreErrorKind.response);
        }
        final roomId = item["rid"]?.toString().trim() ?? "";
        if (roomId.isEmpty || roomId == "null") {
          throw CoreError("斗鱼搜索房间缺少 rid", kind: CoreErrorKind.response);
        }
        var roomItem = LiveRoomItem(
          roomId: roomId,
          title: item["roomName"]?.toString() ?? "",
          cover: item["roomSrc"]?.toString() ?? "",
          userName: item["nickName"]?.toString() ?? "",
          online: parseHotNum(item["hot"].toString()),
        );
        items.add(roomItem);
      }
      final hasMore = rawItems.length == 20;
      return LiveSearchRoomResult(
        hasMore: hasMore,
        items: items,
        metadata: LiveSearchMetadata(
          continuation:
              hasMore ? SearchContinuation.more : SearchContinuation.done,
          origin: SearchOrigin.native,
        ),
      );
    } on CoreCancelledError {
      rethrow;
    } on CoreError {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        CoreError(
          "斗鱼搜索房间响应解析失败",
          kind: CoreErrorKind.response,
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/betard/$roomId",
      queryParameters: {},
      header: {
        if (cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43',
      },
    );
    dynamic decoded = result;
    if (result is String) {
      try {
        decoded = json.decode(result);
      } on FormatException catch (error) {
        throw CoreError(
          "斗鱼房间信息响应格式错误",
          kind: CoreErrorKind.response,
          cause: error,
        );
      }
    }
    if (decoded is! Map || decoded["room"] is! Map) {
      throw CoreError("斗鱼房间信息响应格式错误", kind: CoreErrorKind.response);
    }

    final roomInfo = decoded["room"] as Map;
    final canonicalRoomId = roomInfo["room_id"]?.toString().trim() ?? "";
    final numericRoomId = int.tryParse(canonicalRoomId);
    if (!RegExp(r'^\d+$').hasMatch(canonicalRoomId) ||
        numericRoomId == null ||
        numericRoomId <= 0) {
      throw CoreError("斗鱼房间信息缺少有效房间号", kind: CoreErrorKind.response);
    }
    return roomInfo;
  }

  _DouyuRoomStatus _parseRoomStatus(Map roomInfo) {
    final showStatus = _parseIntegerFlag(roomInfo["show_status"]);
    final videoLoop = _parseIntegerFlag(roomInfo["videoLoop"]);
    final isRecord = videoLoop == 1;
    final state = isRecord || showStatus == 1
        ? LiveStatusState.live
        : showStatus == 2 && videoLoop == 0
            ? LiveStatusState.offline
            : LiveStatusState.unknown;
    return _DouyuRoomStatus(
      state: state,
      isRecord: isRecord,
      isLiveStream: showStatus == 1 && !isRecord,
    );
  }

  int? _parseIntegerFlag(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchUser",
      queryParameters: {
        "kw": keyword,
        "page": page,
        "pageSize": 20,
        "filterType": 1,
      },
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
      cancellation: cancellation,
    );

    try {
      if (result is! Map) {
        throw CoreError("斗鱼搜索主播响应格式错误", kind: CoreErrorKind.response);
      }
      if (result['error'] != 0) {
        throw CoreError(
          result['msg']?.toString() ?? '斗鱼主播搜索失败',
          kind: CoreErrorKind.search,
        );
      }
      final data = result['data'];
      final rawItems = data is Map ? data['relateUser'] : null;
      if (rawItems is! List) {
        throw CoreError("斗鱼搜索主播响应格式错误", kind: CoreErrorKind.response);
      }
      var items = <LiveAnchorItem>[];
      for (var item in rawItems) {
        if (item is! Map || item["anchorInfo"] is! Map) {
          throw CoreError("斗鱼搜索主播响应格式错误", kind: CoreErrorKind.response);
        }
        final anchorInfo = item["anchorInfo"] as Map;
        final roomId = anchorInfo["rid"]?.toString().trim() ?? "";
        if (roomId.isEmpty || roomId == "null") {
          throw CoreError("斗鱼搜索主播缺少 rid", kind: CoreErrorKind.response);
        }
        var liveStatus =
            (int.tryParse(anchorInfo["isLive"].toString()) ?? 0) == 1;
        var roomType = (int.tryParse(anchorInfo["roomType"].toString()) ?? 0);
        var roomItem = LiveAnchorItem(
          roomId: roomId,
          avatar: anchorInfo["avatar"]?.toString() ?? "",
          userName: anchorInfo["nickName"]?.toString() ?? "",
          liveStatus: liveStatus && roomType == 0,
        );
        items.add(roomItem);
      }
      final hasMore = rawItems.length == 20;
      return LiveSearchAnchorResult(
        hasMore: hasMore,
        items: items,
        metadata: LiveSearchMetadata(
          continuation:
              hasMore ? SearchContinuation.more : SearchContinuation.done,
          origin: SearchOrigin.native,
        ),
      );
    } on CoreCancelledError {
      rethrow;
    } on CoreError {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        CoreError(
          "斗鱼搜索主播响应解析失败",
          kind: CoreErrorKind.response,
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final roomInfo = await _getRoomInfo(roomId);
    final status = _parseRoomStatus(roomInfo);
    if (status.state == LiveStatusState.unknown) {
      throw CoreError("斗鱼直播状态未知", kind: CoreErrorKind.response);
    }
    return status.isLiveStream;
  }

  int parseHotNum(String hn) {
    try {
      var num = double.parse(hn.replaceAll("万", ""));
      if (hn.contains("万")) {
        num *= 10000;
      }
      return num.round();
    } catch (_) {
      return -999;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
    LiveRoomDetail? detail,
  }) {
    //尚不支持
    return Future.value([]);
  }

  @override
  Future<List<LiveContributionRankItem>> getContributionRank({
    required String roomId,
    LiveRoomDetail? detail,
  }) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/interact/comm/fanshome/rank/top10",
      queryParameters: {"rid": roomId},
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      },
    );
    final items = (result["data"]?["intimacyRank"] as List?) ?? const [];
    return items.map((item) {
      return LiveContributionRankItem(
        rank: int.tryParse(item["rank"].toString()) ?? 0,
        userName: item["nickname"]?.toString() ?? "",
        avatar: item["avatar"]?.toString() ?? "",
        scoreText: item["value"]?.toString() ?? "0",
        scoreDetail: "亲密度",
      );
    }).toList();
  }
}

class DouyuPlayData {
  final int rate;
  final List<String> cdns;
  final List<int> rateOrder;
  final Map<int, String> rateNames;

  DouyuPlayData(
    this.rate,
    this.cdns, {
    this.rateOrder = const [],
    this.rateNames = const {},
  });
}
