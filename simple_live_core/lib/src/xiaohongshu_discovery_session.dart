import 'dart:async';
import 'dart:convert';

import 'common/core_error.dart';
import 'xiaohongshu_discovery_client.dart';

/// A browser context dedicated to the live directory, never to a playing room.
class XiaohongshuDiscoveryPage {
  const XiaohongshuDiscoveryPage({required this.evaluate, required this.close});

  final Future<void> Function(String script) evaluate;
  final Future<void> Function() close;
}

/// Shared lifecycle and request policy for the App and TV directory signers.
class XiaohongshuDiscoverySession implements XiaohongshuDiscoveryRequestBridge {
  XiaohongshuDiscoverySession({
    required this.openPage,
    this.requestTimeout = const Duration(seconds: 45),
    this.idleTimeout = const Duration(seconds: 30),
  });

  static const pageUrl =
      'https://www.xiaohongshu.com/livelist?channel_id=0&channel_type=web_live_list';
  final Future<XiaohongshuDiscoveryPage> Function(
      void Function(dynamic) receive) openPage;
  final Duration requestTimeout;
  final Duration idleTimeout;
  Future<void> _queue = Future<void>.value();
  XiaohongshuDiscoveryPage? _page;
  final _pending = <String, Completer<dynamic>>{};
  Completer<void> _invalidated = Completer<void>();
  Timer? _idle;
  int _generation = 0;
  int _sequence = 0;
  int _requests = 0;
  bool _closed = false;

  static bool isAllowedRequest(String path, Map<String, dynamic> query) {
    if (path == XiaohongshuDiscoveryClient.categoryPath) return query.isEmpty;
    if (path != XiaohongshuDiscoveryClient.squareFeedPath) return false;
    const keys = {
      'cursorScore',
      'source',
      'category',
      'topRoomIds',
      'preSource',
      'extraInfo',
      'size',
      'extra_info',
    };
    if (query.keys.any((key) => !keys.contains(key))) return false;
    if (query['category'] is! String ||
        !RegExp(r'^\d+$').hasMatch(query['category'] as String)) {
      return false;
    }
    if (query['cursorScore'] is! String ||
        (query['cursorScore'] as String).isEmpty) {
      return false;
    }
    final topRoomIds = query['topRoomIds'];
    if (query.containsKey('topRoomIds') &&
        (topRoomIds is! List || topRoomIds.isNotEmpty)) {
      return false;
    }
    return query.entries.every((entry) =>
        entry.key == 'topRoomIds' ||
        entry.value is String ||
        entry.value is num);
  }

  @override
  Future<dynamic> requestDiscovery({
    required String path,
    Map<String, dynamic> query = const {},
  }) {
    if (!isAllowedRequest(path, query)) {
      return Future<dynamic>.error(CoreError('小红书列表会话仅允许已确认的只读请求'));
    }
    if (_closed) return Future<dynamic>.error(CoreCancelledError());
    _idle?.cancel();
    final generation = _generation;
    final invalidated = _invalidated.future;
    final parameters = Map<String, dynamic>.unmodifiable(query);
    _requests++;
    final task = _queue.then((_) async {
      if (_closed || generation != _generation) throw CoreCancelledError();
      return _request(path, parameters, generation, invalidated);
    }).whenComplete(() {
      _requests--;
      if (!_closed && _requests == 0) {
        _idle = Timer(idleTimeout, () => _releasePage().ignore());
      }
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<dynamic> _request(String path, Map<String, dynamic> query,
      int generation, Future<void> invalidated) async {
    final deadline = DateTime.now().add(requestTimeout);
    final cancelled =
        invalidated.then<dynamic>((_) => throw CoreCancelledError());
    cancelled.ignore();
    Future<T> within<T>(Future<T> future) async {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('directory deadline');
      }
      final value =
          await Future.any<dynamic>([future, cancelled]).timeout(remaining);
      if (_closed || generation != _generation) throw CoreCancelledError();
      return value as T;
    }

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final id = 'discovery:${++_sequence}';
        final response = Completer<dynamic>();
        response.future.ignore();
        try {
          if (_page == null) {
            var abandoned = false;
            final creating = openPage(receive);
            creating.then((page) {
              if (abandoned || _closed || generation != _generation) {
                page.close().ignore();
              }
            }, onError: (Object _, StackTrace __) {});
            try {
              _page = await within(creating);
            } catch (_) {
              abandoned = true;
              rethrow;
            }
          }
          _pending[id] = response;
          await within(_page!
              .evaluate(buildRequestScript(id: id, path: path, query: query)));
          return await within(response.future);
        } on CoreError catch (error) {
          if (attempt != 0 || error.statusCode != 406) rethrow;
          await within(_releasePage());
        } finally {
          _pending.remove(id);
        }
      }
    } on TimeoutException {
      await _releasePage();
      throw CoreError('小红书直播列表加载超时', kind: CoreErrorKind.network);
    }
    throw CoreError('小红书直播列表暂不可用');
  }

  void receive(dynamic payload) {
    try {
      final data = payload is String ? jsonDecode(payload) : payload;
      if (data is! Map) return;
      final pending = _pending.remove(data['id']);
      if (pending == null || pending.isCompleted) return;
      final status = int.tryParse('${data['status']}') ?? 0;
      if (data['ok'] == true) {
        pending.complete(data['data']);
      } else {
        pending.completeError(CoreError(
          status == 406 ? '小红书列表网页签名已失效' : '小红书直播列表请求失败',
          statusCode: status,
          kind: status == 0 ? CoreErrorKind.network : CoreErrorKind.http,
        ));
      }
    } catch (_) {
      // Ignore messages that do not belong to a directory request.
    }
  }

  Future<void> _releasePage() async {
    final page = _page;
    _page = null;
    if (page != null) await page.close();
  }

  /// Invalidate both queued work and a response/creation already in flight.
  Future<void> reset() async {
    _idle?.cancel();
    _generation++;
    if (!_invalidated.isCompleted) _invalidated.complete();
    _invalidated = Completer<void>();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(CoreCancelledError());
    }
    _pending.clear();
    await _releasePage();
  }

  Future<void> close() async {
    _closed = true;
    await reset();
  }

  static String buildRequestScript({
    required String id,
    required String path,
    required Map<String, dynamic> query,
  }) {
    if (!isAllowedRequest(path, query)) {
      throw ArgumentError('directory request');
    }
    final payload = jsonEncode({'id': id, 'path': path, 'query': query});
    return '''(async function() {
      const args = $payload;
      function send(value) {
        const message = JSON.stringify(value);
        if (window.chrome && window.chrome.webview && window.chrome.webview.postMessage) {
          window.chrome.webview.postMessage(message);
        } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.XiaohongshuBridge) {
          window.webkit.messageHandlers.XiaohongshuBridge.postMessage(message);
        } else if (window.XiaohongshuBridge) {
          window.XiaohongshuBridge.postMessage(message);
        } else if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('XiaohongshuBridge', message);
        }
      }
      try {
        // Use the PC page's own GET wrappers. Their HTTP client supplies all
        // signing/fingerprint headers; the live-room H5 signer is different.
        let runtime;
        let api;
        for (let i = 0; i < 100; i++) {
          const chunks = window.webpackChunkxhs_pc_web;
          if (chunks && typeof chunks.push === 'function') {
            chunks.push([[args.id + ':' + i], {}, function(require) { runtime = require; }]);
          }
          if (runtime && runtime.m) {
            const moduleId = Object.keys(runtime.m).find(function(id) {
              const source = String(runtime.m[id]);
              return source.includes('/api/sns/red/live/web/feed/category') &&
                source.includes('/api/sns/red/live/web/feed/v1/squarefeed');
            });
            if (moduleId) {
              const exports = runtime(moduleId);
              const name = args.path === '/api/sns/red/live/web/feed/category'
                ? 'getApiSnsRedLiveWebFeedCategory'
                : 'getApiSnsRedLiveWebFeedV1Squarefeed';
              api = Object.values(exports).find(function(value) {
                return typeof value === 'function' && value.name === name;
              });
              if (api) break;
            }
          }
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        if (!api) { send({id: args.id, ok: false, status: 406}); return; }
        const result = await api({
          params: args.query,
          baseURL: 'https://live-room.xiaohongshu.com',
          transform: true,
          withCredentials: true,
        });
        // transform:true returns the API's data object. Normalize it to the
        // same envelope used by core's raw-response test seam.
        const businessError = result && (result.success === false ||
          (result.code != null && String(result.code) !== '0'));
        const data = businessError ? result : {success: true, data: result};
        send({id: args.id, ok: true, status: 200, data});
      } catch (error) {
        const status = Number(error && (error.status ||
          (error.response && error.response.status))) || 0;
        send({id: args.id, ok: false, status});
      }
    })();''';
  }
}
