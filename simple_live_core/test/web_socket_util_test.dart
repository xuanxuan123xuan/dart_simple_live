import 'dart:async';

import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:test/test.dart';

class _FakeConnection implements WebSocketConnection {
  final StreamController<dynamic> controller = StreamController<dynamic>();
  final List<dynamic> sent = <dynamic>[];
  bool closed = false;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void add(dynamic message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _FakeTimer implements Timer {
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  _FakeTimer(this.callback);

  void fire() {
    if (!_active) return;
    _active = false;
    _tick += 1;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('initial failure schedules one retry and uses a backup url', () async {
    final calls = <String>[];
    final backupConnection = _FakeConnection();
    final timers = <_FakeTimer>[];
    var attempt = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.test/ws',
      backupUrls: const ['wss://backup.test/ws'],
      heartBeatTime: 0,
      connector: (url, _) {
        calls.add(url);
        if (attempt++ == 0) throw StateError('initial failure');
        return backupConnection;
      },
      retryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await socket.connect();
    expect(calls, ['wss://primary.test/ws']);
    expect(timers, hasLength(1));

    timers.single.fire();
    await _flushAsync();
    expect(calls, ['wss://primary.test/ws', 'wss://backup.test/ws']);
    expect(socket.status, SocketStatus.connected);
    socket.close();
  });

  test('stream errors enter the same retry path', () async {
    final first = _FakeConnection();
    final second = _FakeConnection();
    final connections = <_FakeConnection>[first, second];
    final timers = <_FakeTimer>[];
    var index = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.test/ws',
      backupUrls: const ['wss://backup.test/ws'],
      heartBeatTime: 0,
      connector: (_, __) => connections[index++],
      retryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await socket.connect();
    first.controller.addError(StateError('stream failure'));
    await _flushAsync();
    expect(timers, hasLength(1));

    timers.single.fire();
    await _flushAsync();
    expect(index, 2);
    expect(socket.status, SocketStatus.connected);
    socket.close();
  });

  test('stops after the configured retry limit', () async {
    final timers = <_FakeTimer>[];
    final closeMessages = <String>[];
    var calls = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.test/ws',
      backupUrls: const ['wss://backup.test/ws'],
      heartBeatTime: 0,
      maxReconnectTime: 2,
      connector: (_, __) {
        calls += 1;
        throw StateError('failure $calls');
      },
      retryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
      onClose: closeMessages.add,
    );

    await socket.connect();
    timers[0].fire();
    await _flushAsync();
    timers[1].fire();
    await _flushAsync();

    expect(calls, 3);
    expect(socket.status, SocketStatus.closed);
    expect(closeMessages.last, contains('重连超过最大次数'));
    socket.close();
  });

  test('a received message resets the retry counter', () async {
    final connection = _FakeConnection();
    final timers = <_FakeTimer>[];
    var calls = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.test/ws',
      heartBeatTime: 0,
      connector: (_, __) {
        calls += 1;
        if (calls == 1) throw StateError('first failure');
        return connection;
      },
      retryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await socket.connect();
    expect(socket.reconnectTime, 1);
    timers.single.fire();
    await _flushAsync();
    connection.controller.add('hello');
    await _flushAsync();
    expect(socket.reconnectTime, 0);
    socket.close();
  });

  test('manual close cancels a pending retry', () async {
    final timers = <_FakeTimer>[];
    var calls = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.test/ws',
      heartBeatTime: 0,
      connector: (_, __) {
        calls += 1;
        throw StateError('failure');
      },
      retryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await socket.connect();
    expect(timers.single.isActive, isTrue);
    socket.close();
    expect(timers.single.isActive, isFalse);
    timers.single.fire();
    await _flushAsync();
    expect(calls, 1);
  });

  test('deduplicates and limits candidate urls for one connection round',
      () async {
    final calls = <String>[];
    final timers = <_FakeTimer>[];
    final socket = WebScoketUtils(
      url: 'wss://primary.test/ws',
      backupUrl: 'wss://backup-a.test/ws',
      backupUrls: const [
        'wss://backup-a.test/ws',
        'wss://backup-b.test/ws',
      ],
      heartBeatTime: 0,
      maxConnectAttempts: 2,
      connector: (url, _) {
        calls.add(url);
        throw StateError('failure');
      },
      retryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    expect(socket.connectUrls, [
      'wss://primary.test/ws',
      'wss://backup-a.test/ws',
      'wss://backup-b.test/ws',
    ]);

    await socket.connect();
    timers[0].fire();
    await _flushAsync();
    timers[1].fire();
    await _flushAsync();

    expect(calls, [
      'wss://primary.test/ws',
      'wss://backup-a.test/ws',
      'wss://primary.test/ws',
    ]);
    socket.close();
  });
}
