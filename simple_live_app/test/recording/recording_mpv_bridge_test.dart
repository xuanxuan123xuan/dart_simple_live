import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/services/recording/recording_mpv_bridge.dart';

class _NativeLifetime extends Fake implements NativePlayer {
  _NativeLifetime({this.disposed = false, this.disposeDuringHandle = false});
  @override
  bool disposed;
  bool disposeDuringHandle;
  bool handleRead = false;
  @override
  Future<int> get handle async {
    handleRead = true;
    if (disposeDuringHandle) disposed = true;
    return 1;
  }
}

class _RetryDrainBridge extends IsolateRecordingMpvBridge {
  _RetryDrainBridge(super.port, super.replies) : super.forTransport();
  bool rejectDrain = true;
  @override
  Future<void> drain() async {
    if (rejectDrain) {
      rejectDrain = false;
      throw StateError('transient drain failure before destroy');
    }
    await super.drain();
  }
}

void main() {
  test('create rejects a player disposed before resolving its handle',
      () async {
    final native = _NativeLifetime(disposed: true);
    await expectLater(
        IsolateRecordingMpvBridge.create(Player(platformPlayer: native)),
        throwsStateError);
    expect(native.handleRead, isFalse);
  });

  test('create checks disposal again after resolving the native handle',
      () async {
    final native = _NativeLifetime(disposeDuringHandle: true);
    await expectLater(
        IsolateRecordingMpvBridge.create(Player(platformPlayer: native)),
        throwsStateError);
    expect(native.handleRead, isTrue);
  });

  test('close can retry drain failure before any destroy request', () async {
    final requests = ReceivePort();
    final replies = ReceivePort();
    final bridge = _RetryDrainBridge(requests.sendPort, replies);
    var destroyRequests = 0;
    requests.listen((dynamic message) {
      final request = message as List<dynamic>;
      if (request[1] == 'close') destroyRequests++;
      replies.sendPort.send([request[0], 0, '']);
    });
    await expectLater(bridge.close(), throwsStateError);
    expect(destroyRequests, 0);
    await bridge.close();
    expect(destroyRequests, 1);
    requests.close();
  });

  test('close never retries a destroy with an uncertain failed acknowledgement',
      () async {
    final requests = ReceivePort();
    final replies = ReceivePort();
    final bridge =
        IsolateRecordingMpvBridge.forTransport(requests.sendPort, replies);
    var destroyRequests = 0;
    requests.listen((dynamic message) {
      final request = message as List<dynamic>;
      destroyRequests++;
      replies.sendPort.send([request[0], -12, 'uncertain destroy']);
    });
    await expectLater(bridge.close(), throwsA(isA<RecordingMpvError>()));
    await expectLater(bridge.close(), throwsA(isA<RecordingMpvError>()));
    expect(destroyRequests, 1);
    replies.close();
    requests.close();
  });
  test(
      'negative immediate/reply result is an error instead of log-only success',
      () async {
    final requests = ReceivePort();
    final replies = ReceivePort();
    final bridge =
        IsolateRecordingMpvBridge.forTransport(requests.sendPort, replies);
    requests.listen((dynamic message) {
      final request = message as List<dynamic>;
      replies.sendPort
          .send([request[0], request[1] == 'close' ? 0 : -12, 'command']);
    });
    await expectLater(
        bridge.command(['set', 'stream-record', 'raw.mkv']),
        throwsA(isA<RecordingMpvError>()
            .having((error) => error.code, 'code', -12)));
    await expectLater(bridge.getProperty('vf-metadata/test'),
        throwsA(isA<RecordingMpvError>()));
    await bridge.close();
    requests.close();
  });

  test(
      'late native reply remains owned and close drains before destroying client',
      () async {
    final requests = ReceivePort();
    final replies = ReceivePort();
    final bridge =
        IsolateRecordingMpvBridge.forTransport(requests.sendPort, replies);
    final commandSeen = Completer<int>();
    var closeSent = false;
    requests.listen((dynamic message) {
      final request = message as List<dynamic>;
      if (request[1] == 'close') {
        closeSent = true;
        replies.sendPort.send([request[0], 0, '']);
      } else {
        commandSeen.complete(request[0] as int);
      }
    });
    final command = bridge.command(['set', 'stream-record', 'raw.mkv']);
    final id = await commandSeen.future;
    await expectLater(command.timeout(const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()));
    var closed = false;
    final closing = bridge.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeSent, isFalse);
    expect(closed, isFalse);
    await expectLater(bridge.command(['stop']), throwsStateError);
    replies.sendPort.send([id, 0, '']);
    await closing;
    expect(closeSent, isTrue);
    expect(closed, isTrue);
    requests.close();
  });

  test('request IDs isolate metadata responses from command replies', () async {
    final requests = ReceivePort();
    final replies = ReceivePort();
    final bridge =
        IsolateRecordingMpvBridge.forTransport(requests.sendPort, replies);
    final received = <List<dynamic>>[];
    requests.listen((dynamic message) {
      final request = message as List<dynamic>;
      if (request[1] == 'close') {
        replies.sendPort.send([request[0], 0, '']);
      } else {
        received.add(request);
        if (received.length == 2) {
          replies.sendPort.send([received[1][0], 0, '{"fp0.pts":1}']);
          replies.sendPort.send([received[0][0], 0, '']);
        }
      }
    });
    final command = bridge.command(['set', 'pause', 'yes']);
    final property = bridge.getProperty('vf-metadata/test');
    expect(await property, '{"fp0.pts":1}');
    await command;
    await bridge.close();
    requests.close();
  });
}
