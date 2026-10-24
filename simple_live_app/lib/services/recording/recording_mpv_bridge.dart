import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:media_kit/media_kit.dart';
// The resolved media_kit library must also back the secondary client.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;

/// All futures represent native completion, including replies arriving after a
/// caller's timeout. Never destroy the player until [close] has completed.
abstract interface class RecordingMpvBridge {
  Future<void> command(List<String> command);
  Future<String> getProperty(String name);
  Future<void> drain();
  Future<void> close();
}

class RecordingMpvError implements Exception {
  const RecordingMpvError(this.code, this.operation);
  static const propertyUnavailable =
      mpv.mpv_error.MPV_ERROR_PROPERTY_UNAVAILABLE;
  final int code;
  final String operation;
  @override
  String toString() => 'mpv $operation failed ($code)';
}

/// Initialization failed after the worker confirmed partial-client cleanup.
/// An unexpected isolate failure has no such guarantee and uses StateError.
class RecordingMpvInitializationError implements Exception {
  const RecordingMpvInitializationError(this.message);
  final String message;
  @override
  String toString() => message;
}

class IsolateRecordingMpvBridge implements RecordingMpvBridge {
  IsolateRecordingMpvBridge._(this._port, this._replies);

  /// Protocol seam for tests; production uses [create] and a native worker.
  IsolateRecordingMpvBridge.forTransport(this._port, this._replies) {
    _replies
        .listen((dynamic message) => _handleReply(message as List<dynamic>));
  }

  final SendPort _port;
  final ReceivePort _replies;
  final Map<int, Completer<String>> _pending = {};
  int _nextId = 0;
  bool _closing = false;
  bool _destroyRequested = false;
  Future<void>? _closeFuture;
  Object? _workerFailure;
  ReceivePort? _failures;

  static Future<IsolateRecordingMpvBridge> create(Player player) async {
    final native = player.platform as NativePlayer;
    if (native.disposed) throw StateError('Recording player has been disposed');
    final address = await native.handle;
    if (native.disposed) throw StateError('Recording player has been disposed');
    return _create(address);
  }

  /// The worker owns the complete headless verifier, including initialization
  /// and destruction. No media_kit on_load hook runs on the UI isolate.
  static Future<IsolateRecordingMpvBridge> createVerifier() => _create(0);

  static Future<IsolateRecordingMpvBridge> _create(int address) async {
    final replies = ReceivePort();
    final failures = ReceivePort();
    final ready = Completer<SendPort>();
    IsolateRecordingMpvBridge? bridge;
    failures.listen((dynamic error) {
      final failure = StateError('Recording native worker failed: $error');
      if (!ready.isCompleted) {
        ready.completeError(failure);
      } else {
        bridge?._workerFailed(failure);
      }
    });
    replies.listen((dynamic message) {
      final value = message as List<dynamic>;
      if (value[0] == 'ready') {
        ready.complete(value[1] as SendPort);
      } else if (value[0] == 'initError') {
        ready
            .completeError(RecordingMpvInitializationError(value[1] as String));
        replies.close();
      } else {
        bridge?._handleReply(value);
      }
    });
    try {
      await Isolate.spawn(
          _recordingWorker, [replies.sendPort, NativeLibrary.path, address],
          onError: failures.sendPort, errorsAreFatal: true);
      bridge = IsolateRecordingMpvBridge._(await ready.future, replies);
      bridge._failures = failures;
      return bridge;
    } on Object {
      replies.close();
      failures.close();
      rethrow;
    }
  }

  void _workerFailed(Object failure) {
    _workerFailure = failure;
    for (final completer in _pending.values) {
      completer.completeError(failure);
    }
    _pending.clear();
  }

  void _handleReply(List<dynamic> value) {
    final completer = _pending.remove(value[0] as int);
    if (completer == null) return;
    final code = value[1] as int;
    if (code < 0) {
      completer.completeError(RecordingMpvError(code, value[2] as String));
    } else {
      completer.complete(value[2] as String);
    }
  }

  Future<String> _request(String kind, Object payload) {
    if (_workerFailure != null) return Future.error(_workerFailure!);
    if (_closing) {
      return Future.error(StateError('Recording bridge is closing'));
    }
    return _send(kind, payload);
  }

  Future<String> _send(String kind, Object payload) {
    final id = ++_nextId;
    final completer = Completer<String>();
    _pending[id] = completer;
    _port.send([id, kind, payload]);
    return completer.future;
  }

  @override
  Future<void> command(List<String> command) async {
    await _request('command', command);
  }

  @override
  Future<String> getProperty(String name) => _request('property', name);

  @override
  Future<void> drain() async {
    if (_workerFailure != null) throw _workerFailure!;
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.values.map((item) => item.future
          .then<void>((_) {}, onError: (Object _, StackTrace __) {})));
    }
    if (_workerFailure != null) throw _workerFailure!;
  }

  @override
  Future<void> close() =>
      _closeFuture ??= _close().onError((Object error, StackTrace stackTrace) {
        // Only retry a failure before destruction was requested, with a live
        // worker. A missing destroy acknowledgement cannot prove client safety.
        if (!_destroyRequested && _workerFailure == null) _closeFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<void> _close() async {
    _closing = true;
    await drain();
    _destroyRequested = true;
    await _send('close', '');
    _replies.close();
    _failures?.close();
  }
}

/// This isolate alone consumes events from its own mpv client. The player's
/// media_kit event queue remains untouched. Event-owned strings are copied before
/// the next wait_event call invalidates them.
void _recordingWorker(List<dynamic> arguments) {
  final output = arguments[0] as SendPort;
  final requests = ReceivePort();
  Pointer<mpv.mpv_handle> client = nullptr;
  mpv.MPV? initializedApi;
  Timer? polling;
  try {
    final api = mpv.MPV(DynamicLibrary.open(arguments[1] as String));
    initializedApi = api;
    final ownsCore = arguments[2] == 0;
    if (ownsCore) {
      client = api.mpv_create();
      if (client == nullptr) throw StateError('Unable to create verifier core');
      for (final entry in {
        'config': 'no',
        'terminal': 'no',
        'vo': 'null',
        'ao': 'null',
        'idle': 'yes',
        'hwdec': 'no',
      }.entries) {
        final name = entry.key.toNativeUtf8();
        final value = entry.value.toNativeUtf8();
        try {
          final error =
              api.mpv_set_option_string(client, name.cast(), value.cast());
          if (error < 0) {
            throw RecordingMpvError(error, 'verifier ${entry.key}');
          }
        } finally {
          calloc.free(name);
          calloc.free(value);
        }
      }
      final error = api.mpv_initialize(client);
      if (error < 0) throw RecordingMpvError(error, 'initialize verifier');
    } else {
      final name = 'simple_live_recording'.toNativeUtf8();
      try {
        client = api.mpv_create_client(
            Pointer<mpv.mpv_handle>.fromAddress(arguments[2] as int),
            name.cast());
      } finally {
        calloc.free(name);
      }
    }
    if (client == nullptr) {
      throw StateError('Unable to create recording client');
    }
    final operations = <int, String>{};
    requests.listen((dynamic raw) {
      final request = raw as List<dynamic>;
      final id = request[0] as int;
      final kind = request[1] as String;
      if (kind == 'close') {
        polling?.cancel();
        if (ownsCore) {
          api.mpv_terminate_destroy(client);
        } else {
          api.mpv_destroy(client);
        }
        output.send([id, 0, '']);
        requests.close();
        return;
      }
      int result;
      if (kind == 'command') {
        final values = (request[2] as List<dynamic>).cast<String>();
        final strings = values.map((value) => value.toNativeUtf8()).toList();
        final pointers = calloc<Pointer<Int8>>(strings.length + 1);
        try {
          for (var i = 0; i < strings.length; i++) {
            pointers[i] = strings[i].cast();
          }
          result = api.mpv_command_async(client, id, pointers);
        } finally {
          for (final string in strings) {
            calloc.free(string);
          }
          calloc.free(pointers);
        }
      } else {
        final name = (request[2] as String).toNativeUtf8();
        try {
          result = api.mpv_get_property_async(
              client, id, name.cast(), mpv.mpv_format.MPV_FORMAT_STRING);
        } finally {
          calloc.free(name);
        }
      }
      if (result < 0) {
        output.send([id, result, '$kind ${request[2]}']);
      } else {
        operations[id] = kind;
      }
    });
    polling = Timer.periodic(const Duration(milliseconds: 5), (_) {
      for (var count = 0; count < 128; count++) {
        final event = api.mpv_wait_event(client, 0).ref;
        if (event.event_id == mpv.mpv_event_id.MPV_EVENT_NONE) break;
        if (event.event_id != mpv.mpv_event_id.MPV_EVENT_COMMAND_REPLY &&
            event.event_id != mpv.mpv_event_id.MPV_EVENT_GET_PROPERTY_REPLY) {
          continue;
        }
        final kind = operations.remove(event.reply_userdata);
        if (kind == null) continue;
        var value = '';
        if (kind == 'property' && event.error >= 0 && event.data != nullptr) {
          final property = event.data.cast<mpv.mpv_event_property>().ref;
          if (property.format == mpv.mpv_format.MPV_FORMAT_STRING &&
              property.data != nullptr) {
            final string = property.data.cast<Pointer<Utf8>>().value;
            if (string != nullptr) value = string.toDartString();
          }
        }
        output.send([
          event.reply_userdata,
          event.error,
          event.error < 0 ? kind : value
        ]);
      }
    });
    output.send(['ready', requests.sendPort]);
  } on Object catch (error) {
    polling?.cancel();
    requests.close();
    if (client != nullptr) initializedApi?.mpv_destroy(client);
    output.send(['initError', '$error']);
  }
}
