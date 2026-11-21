import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart' as shelf;
import 'package:simple_live_core/simple_live_core.dart';

typedef XiaohongshuRelayRequest = Future<dynamic> Function({
  required String path,
  Map<String, dynamic> query,
});

/// Exposes read-only Xiaohongshu live discovery through the existing LAN
/// sync server. A distinct discovery client is kept for each TV browsing run
/// so its pagination state never touches the app's live-directory client.
class XiaohongshuDiscoveryLanRelay {
  XiaohongshuDiscoveryLanRelay({
    required XiaohongshuRelayRequest requestDiscovery,
    required bool Function() isAvailable,
    DateTime Function()? now,
    this.sessionLifetime = const Duration(minutes: 10),
    this.maxSessions = 8,
    this.maxPage = 100,
    this.maxExpiredSessionIds = 64,
    String Function()? pairingCodeGenerator,
  })  : _requestDiscovery = requestDiscovery,
        _isAvailable = isAvailable,
        _now = now ?? DateTime.now,
        _pairingCodeGenerator = pairingCodeGenerator;

  static const String categoriesPath = '/discovery/xiaohongshu/categories';
  static const String roomsPath = '/discovery/xiaohongshu/rooms';
  static const String pairingCodeHeader = 'x-simplelive-pairing-code';
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _digitsPattern = RegExp(r'^\d+$');
  static final RegExp _pagePattern = RegExp(r'^[1-9]\d{0,2}$');
  static final RegExp _pairingCodePattern = RegExp(r'^[0-9]{6}$');

  final XiaohongshuRelayRequest _requestDiscovery;
  final bool Function() _isAvailable;
  final Random _random = Random.secure();
  final DateTime Function() _now;
  final Duration sessionLifetime;
  final int maxSessions;
  final int maxPage;
  final int maxExpiredSessionIds;
  final String Function()? _pairingCodeGenerator;

  final LinkedHashMap<String, _BrowseContext> _sessions =
      LinkedHashMap<String, _BrowseContext>();
  final LinkedHashMap<String, DateTime> _expiredSessionIds =
      LinkedHashMap<String, DateTime>();
  late final XiaohongshuDiscoveryClient _categoriesClient = _newClient();

  String? _pairingCode;
  String? _previousPairingCode;
  bool _pageVisible = false;
  bool _foreground = false;
  int _activeGeneration = 0;

  String? get pairingCode => _pairingCode;

  bool get isActive =>
      _pageVisible && _foreground && _pairingCode != null && _available;

  bool get _available {
    try {
      return _isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Starts one visible-screen lifetime and creates a fresh six-digit code.
  String start() {
    stop();
    final code = _newPairingCode();
    _pairingCode = code;
    return code;
  }

  void setPageVisible(bool value) {
    if (_pageVisible == value) return;
    final wasActive = isActive;
    _pageVisible = value;
    _updateGeneration(wasActive);
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    final wasActive = isActive;
    _foreground = value;
    _updateGeneration(wasActive);
  }

  /// Closes the relay and expires its in-memory browse contexts.
  void stop() {
    _expireBrowseContexts();
    _pageVisible = false;
    _foreground = false;
    _pairingCode = null;
    _activeGeneration++;
  }

  Future<shelf.Response> categoriesRequest(shelf.Request request) async {
    final blocked = _preflight(request);
    if (blocked != null) return blocked;
    final generation = _activeGeneration;
    if (request.requestedUri.queryParametersAll.isNotEmpty) {
      return _error(400, '请求参数无效，请刷新后重试');
    }

    try {
      final categories = await _categoriesClient.getCategories();
      if (!_canServe(generation)) return _unavailable();
      final flattened = <Map<String, String>>[];
      void addChildren(Iterable<LiveSubCategory> children) {
        for (final child in children) {
          if (_digitsPattern.hasMatch(child.id) &&
              child.id.length <= 32 &&
              child.name.trim().isNotEmpty) {
            flattened.add({'id': child.id, 'name': child.name});
          }
          addChildren(child.children);
        }
      }

      for (final category in categories) {
        addChildren(category.children);
      }
      return _json(200, {'categories': flattened});
    } catch (_) {
      return _canServe(generation)
          ? _upstreamUnavailable('小红书直播分类暂不可用，请稍后重试')
          : _unavailable();
    }
  }

  Future<shelf.Response> roomsRequest(shelf.Request request) async {
    final blocked = _preflight(request);
    if (blocked != null) return blocked;
    final generation = _activeGeneration;

    final params = request.requestedUri.queryParametersAll;
    if (params.length != 3 ||
        !params.keys
            .toSet()
            .containsAll(const {'category', 'page', 'session'}) ||
        params.values.any((values) => values.length != 1)) {
      return _error(400, '请求参数无效，请刷新后重试');
    }

    final category = params['category']!.single;
    final rawPage = params['page']!.single;
    final rawSessionId = params['session']!.single;
    if (!_digitsPattern.hasMatch(category) ||
        category.length > 32 ||
        !_pagePattern.hasMatch(rawPage) ||
        !_uuidPattern.hasMatch(rawSessionId)) {
      return _error(400, '请求参数无效，请刷新后重试');
    }
    final page = int.parse(rawPage);
    if (page > maxPage) return _error(400, '列表页数超出范围，请刷新后重试');

    final sessionId = rawSessionId.toLowerCase();
    _expireOldSessions();
    if (_expiredSessionIds.containsKey(sessionId)) {
      return _conflict('浏览会话已过期，请刷新小红书直播列表');
    }

    var context = _sessions[sessionId];
    if (context == null) {
      if (page != 1) {
        return _conflict('浏览会话已失效，请刷新小红书直播列表');
      }
      if (maxSessions <= 0) return _unavailable();
      while (_sessions.length >= maxSessions) {
        final oldestSessionId = _sessions.keys.first;
        _sessions.remove(oldestSessionId);
        _markExpired(oldestSessionId);
      }
      context = _BrowseContext(_newClient(), _now(), category);
      _sessions[sessionId] = context;
    }
    _touchSession(sessionId, context);
    if (context.category != category) {
      return _conflict('浏览会话分类已变化，请刷新小红书直播列表');
    }

    final cachedPage = context.lastSuccessfulPage;
    if (cachedPage?.page == page) return _json(200, cachedPage!.body);

    final existingRequest = context.inFlight;
    if (existingRequest != null && context.inFlightPage == page) {
      return _awaitRoomTask(existingRequest, generation);
    }

    if (existingRequest != null) {
      return _conflict('浏览会话请求尚未完成，请刷新小红书直播列表');
    }

    if (page != context.nextPage || context.stopped) {
      return _conflict('列表页码已变化，请刷新小红书直播列表');
    }

    final task = _loadRooms(
      sessionId: sessionId,
      context: context,
      category: category,
      page: page,
      generation: generation,
    );
    context.inFlightPage = page;
    context.inFlight = task;
    try {
      return await _awaitRoomTask(task, generation);
    } finally {
      if (identical(context.inFlight, task)) {
        context.inFlight = null;
        context.inFlightPage = null;
      }
    }
  }

  Future<shelf.Response> _awaitRoomTask(
    Future<_CachedRelayPage?> task,
    int generation,
  ) async {
    try {
      final result = await task;
      if (!_canServe(generation)) return _unavailable();
      if (result == null) return _conflict('浏览会话已失效，请刷新小红书直播列表');
      return _json(200, result.body);
    } catch (_) {
      return _canServe(generation)
          ? _upstreamUnavailable('小红书直播列表暂不可用，请稍后重试')
          : _unavailable();
    }
  }

  Future<_CachedRelayPage?> _loadRooms({
    required String sessionId,
    required _BrowseContext context,
    required String category,
    required int page,
    required int generation,
  }) async {
    final result = category == '0'
        ? await context.client.getRecommendRooms(page: page)
        : await context.client.getRooms(categoryId: category, page: page);
    if (!_canServe(generation) || !identical(_sessions[sessionId], context)) {
      return null;
    }

    final hasMore = result.hasMore && page < maxPage;
    final body = <String, dynamic>{
      'rooms': result.items
          .map((room) => <String, String>{
                'roomId': room.roomId,
                'title': room.title,
                'cover': room.cover,
                'userName': room.userName,
              })
          .toList(growable: false),
      'hasMore': hasMore,
    };
    final cached = _CachedRelayPage(page, body);
    context.lastSuccessfulPage = cached;
    context.nextPage = page + 1;
    context.stopped = !hasMore;
    context.lastUsedAt = _now();
    _touchSession(sessionId, context);
    return cached;
  }

  XiaohongshuDiscoveryClient _newClient() => XiaohongshuDiscoveryClient(
        request: (path, query) => _requestDiscovery(path: path, query: query),
        isAvailable: () => true,
      );

  shelf.Response? _preflight(shelf.Request request) {
    if (!isActive) return _unavailable();
    final suppliedCode = request.headers[pairingCodeHeader];
    if (suppliedCode != _pairingCode) {
      return _error(401, '连接码错误，请核对手机屏幕上的六位数字');
    }
    return null;
  }

  bool _canServe(int generation) => generation == _activeGeneration && isActive;

  void _updateGeneration(bool wasActive) {
    final activeNow = isActive;
    if (wasActive == activeNow) return;
    _activeGeneration++;
    if (wasActive) _expireBrowseContexts();
  }

  void _expireBrowseContexts() {
    for (final sessionId in _sessions.keys.toList()) {
      _markExpired(sessionId);
    }
    _sessions.clear();
  }

  void _touchSession(String sessionId, _BrowseContext context) {
    context.lastUsedAt = _now();
    _sessions.remove(sessionId);
    _sessions[sessionId] = context;
  }

  void _expireOldSessions() {
    final now = _now();
    for (final entry in _sessions.entries.toList()) {
      if (now.difference(entry.value.lastUsedAt) > sessionLifetime) {
        _sessions.remove(entry.key);
        _markExpired(entry.key);
      }
    }
    for (final entry in _expiredSessionIds.entries.toList()) {
      if (now.difference(entry.value) > sessionLifetime * 2) {
        _expiredSessionIds.remove(entry.key);
      }
    }
  }

  void _markExpired(String sessionId) {
    _expiredSessionIds.remove(sessionId);
    _expiredSessionIds[sessionId] = _now();
    while (_expiredSessionIds.length > maxExpiredSessionIds) {
      _expiredSessionIds.remove(_expiredSessionIds.keys.first);
    }
  }

  String _newPairingCode() {
    var code = _pairingCodeGenerator?.call();
    while (code == null ||
        !_pairingCodePattern.hasMatch(code) ||
        code == _previousPairingCode) {
      code = _random.nextInt(1000000).toString().padLeft(6, '0');
    }
    _previousPairingCode = code;
    return code;
  }

  shelf.Response _unavailable([
    String message = '小红书发现服务当前不可用，请保持页面在前台后重试',
  ]) =>
      _error(503, message);

  shelf.Response _upstreamUnavailable(String message) => _error(502, message);

  shelf.Response _conflict(String message) => _error(409, message);

  shelf.Response _error(int statusCode, String message) =>
      _json(statusCode, {'message': message});

  shelf.Response _json(int statusCode, Map<String, dynamic> body) =>
      shelf.Response(
        statusCode,
        body: jsonEncode(body),
        headers: const {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        },
      );
}

class _BrowseContext {
  _BrowseContext(this.client, this.lastUsedAt, this.category);

  final XiaohongshuDiscoveryClient client;
  final String category;
  int nextPage = 1;
  bool stopped = false;
  _CachedRelayPage? lastSuccessfulPage;
  int? inFlightPage;
  Future<_CachedRelayPage?>? inFlight;
  DateTime lastUsedAt;
}

class _CachedRelayPage {
  _CachedRelayPage(this.page, this.body);

  final int page;
  final Map<String, dynamic> body;
}
