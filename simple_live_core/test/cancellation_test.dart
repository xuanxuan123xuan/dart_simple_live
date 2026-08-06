import 'dart:async';
import 'dart:io' hide HttpClient;

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

class _HangingHttpServer {
  _HangingHttpServer._(this._server);

  final HttpServer _server;
  final Completer<HttpRequest> _requestReceived = Completer<HttpRequest>();

  String get url => 'http://${_server.address.address}:${_server.port}/';

  Future<HttpRequest> get requestReceived => _requestReceived.future;

  static Future<_HangingHttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hangingServer = _HangingHttpServer._(server);
    server.listen((request) {
      if (!hangingServer._requestReceived.isCompleted) {
        hangingServer._requestReceived.complete(request);
      }
    });
    return hangingServer;
  }

  Future<void> close() => _server.close(force: true);
}

class _TrackingCancellation implements CoreCancellation {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};
  int removeCalls = 0;

  @override
  bool get isCancelled => _isCancelled;

  @override
  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  @override
  void cancel([Object? reason]) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  @override
  void removeListener(void Function() listener) {
    removeCalls++;
    _listeners.remove(listener);
  }
}

void main() {
  group('CoreCancellationToken', () {
    test('records cancellation state and reason', () {
      final token = CoreCancellationToken();
      final reason = StateError('screen disposed');

      expect(token.isCancelled, isFalse);
      expect(token.reason, isNull);

      token.cancel(reason);

      expect(token.isCancelled, isTrue);
      expect(token.reason, same(reason));
    });

    test('notifies a listener only once when cancelled repeatedly', () {
      final token = CoreCancellationToken();
      var calls = 0;
      void listener() => calls++;

      token.addListener(listener);
      token.cancel('first');
      token.cancel('second');

      expect(calls, 1);
      expect(token.reason, 'first');
    });

    test('does not notify a removed listener', () {
      final token = CoreCancellationToken();
      var calls = 0;
      void listener() => calls++;

      token.addListener(listener);
      token.removeListener(listener);
      token.cancel();

      expect(calls, 0);
    });

    test('invokes listeners added after cancellation immediately', () {
      final token = CoreCancellationToken();
      token.cancel();
      var calls = 0;

      token.addListener(() => calls++);

      expect(calls, 1);
    });
  });

  group('HttpClient cancellation', () {
    Future<void> expectCancelled(
      Future<void> Function(
              HttpClient client, String url, CoreCancellationToken token)
          request,
    ) async {
      final server = await _HangingHttpServer.start();
      final token = CoreCancellationToken();
      final future = request(HttpClient(), server.url, token);
      try {
        await server.requestReceived;
        token.cancel('test cancellation');
        await expectLater(future, throwsA(isA<CoreCancelledError>()));
      } finally {
        await server.close();
      }
    }

    test('GET cancellation is reported as CoreCancelledError', () async {
      await expectCancelled(
        (client, url, token) async {
          await client.getText(url, cancellation: token);
        },
      );
    });

    test('POST cancellation is reported as CoreCancelledError', () async {
      await expectCancelled(
        (client, url, token) async {
          await client.postJson(url,
              data: {'key': 'value'}, cancellation: token);
        },
      );
    });

    test('HEAD cancellation is reported as CoreCancelledError', () async {
      await expectCancelled(
        (client, url, token) async {
          await client.head(url, cancellation: token);
        },
      );
    });

    test('removes the request listener after a completed request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('ok');
        await request.response.close();
      });
      final cancellation = _TrackingCancellation();
      try {
        final result = await HttpClient().getText(
          'http://${server.address.address}:${server.port}/',
          cancellation: cancellation,
        );

        expect(result, 'ok');
        expect(cancellation.removeCalls, 1);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
