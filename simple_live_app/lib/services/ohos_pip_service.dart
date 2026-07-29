import 'dart:async';

import 'package:flutter/services.dart';
import 'package:simple_live_app/app/utils.dart';

class OhosPipService {
  OhosPipService({
    MethodChannel? channel,
    bool Function()? isOhos,
  })  : _channel = channel ?? const MethodChannel('simple_live/ohos_pip'),
        _isOhos = isOhos ?? (() => Utils.isOhos);

  static final OhosPipService instance = OhosPipService();

  final MethodChannel _channel;
  final bool Function() _isOhos;
  final StreamController<bool> _stateController =
      StreamController<bool>.broadcast(sync: true);
  bool _initialized = false;
  bool _enabled = false;

  Stream<bool> get stateChanges => _stateController.stream;
  bool get enabled => _enabled;

  void initialize() {
    if (_initialized || !_isOhos()) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler(_onMethodCall);
  }

  Future<bool> isAvailable() async {
    if (!_isOhos()) {
      return false;
    }
    initialize();
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> enter({required double width, required double height}) async {
    if (!_isOhos()) {
      return false;
    }
    initialize();
    return await _channel.invokeMethod<bool>('enter', _size(width, height)) ??
        false;
  }

  Future<bool> prepareAuto({
    required double width,
    required double height,
  }) async {
    if (!_isOhos()) {
      return false;
    }
    initialize();
    return await _channel.invokeMethod<bool>(
          'prepareAuto',
          _size(width, height),
        ) ??
        false;
  }

  Future<void> cancelAuto() async {
    if (!_isOhos()) {
      return;
    }
    initialize();
    await _channel.invokeMethod<void>('cancelAuto');
  }

  Future<void> exit() async {
    if (!_isOhos()) {
      return;
    }
    initialize();
    await _channel.invokeMethod<void>('exit');
  }

  Future<void> dispose() async {
    if (_initialized) {
      _channel.setMethodCallHandler(null);
      _initialized = false;
    }
    await _stateController.close();
  }

  Map<String, int> _size(double width, double height) {
    return {
      'width': width > 0 ? width.round() : 16,
      'height': height > 0 ? height.round() : 9,
    };
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'stateChanged') {
      return;
    }
    final arguments = call.arguments;
    final enabled = arguments is Map && arguments['enabled'] == true;
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    _stateController.add(enabled);
  }
}
