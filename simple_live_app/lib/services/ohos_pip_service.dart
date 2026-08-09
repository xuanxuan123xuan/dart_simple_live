import 'dart:async';

import 'package:flutter/services.dart';
import 'package:simple_live_app/app/utils.dart';

class OhosPipService {
  OhosPipService({
    MethodChannel? channel,
    MethodChannel? capabilitiesChannel,
    bool Function()? isOhos,
  })  : _channel = channel ?? const MethodChannel('simple_live/ohos_pip'),
        _capabilitiesChannel = capabilitiesChannel ??
            const MethodChannel('simple_live/ohos_capabilities'),
        _isOhos = isOhos ?? (() => Utils.isOhos);

  static final OhosPipService instance = OhosPipService();

  final MethodChannel _channel;
  final MethodChannel _capabilitiesChannel;
  final bool Function() _isOhos;
  StreamController<bool> _stateController =
      StreamController<bool>.broadcast(sync: true);
  bool _initialized = false;
  bool _disposed = false;
  bool _enabled = false;
  Future<PipCapabilities>? _capabilitiesFuture;

  Stream<bool> get stateChanges => _stateController.stream;
  bool get enabled => _enabled;

  Future<PipCapabilities> getCapabilities({bool refresh = false}) {
    if (!_isOhos()) {
      return Future<PipCapabilities>.value(PipCapabilities.unsupported);
    }
    if (refresh) {
      _capabilitiesFuture = null;
    }
    return _capabilitiesFuture ??= _loadCapabilities();
  }

  Future<PipCapabilities> _loadCapabilities() async {
    try {
      final result =
          await _capabilitiesChannel.invokeMapMethod<String, dynamic>(
        'getPipCapabilities',
      );
      return PipCapabilities.fromMap(result);
    } on PlatformException {
      return PipCapabilities.unsupported;
    } on MissingPluginException {
      return PipCapabilities.unsupported;
    }
  }

  void initialize() {
    if (_initialized || !_isOhos()) {
      return;
    }
    // Allow re-initialization after dispose() by recreating the closed
    // StreamController instead of emitting into a closed one (StateError).
    if (_disposed) {
      _stateController = StreamController<bool>.broadcast(sync: true);
      _disposed = false;
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
    if (!(await getCapabilities()).pipAvailable) {
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
    if (!(await getCapabilities()).pipAutoOnLeaveSupported) {
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
    // Mark disposed so that a later initialize()/isAvailable() recreates the
    // StreamController instead of emitting into the closed one (StateError).
    _disposed = true;
    _enabled = false;
    _capabilitiesFuture = null;
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

class PipCapabilities {
  const PipCapabilities({
    required this.pipAvailable,
    required this.pipAutoOnLeaveSupported,
    required this.pipCanHideDanmaku,
  });

  static const unsupported = PipCapabilities(
    pipAvailable: false,
    pipAutoOnLeaveSupported: false,
    pipCanHideDanmaku: false,
  );

  static const supported = PipCapabilities(
    pipAvailable: true,
    pipAutoOnLeaveSupported: true,
    pipCanHideDanmaku: true,
  );

  factory PipCapabilities.fromMap(Map<String, dynamic>? values) {
    if (values == null) {
      return unsupported;
    }
    final available = values['pipAvailable'] == true;
    return PipCapabilities(
      pipAvailable: available,
      pipAutoOnLeaveSupported:
          available && values['pipAutoOnLeaveSupported'] == true,
      pipCanHideDanmaku: available && values['pipCanHideDanmaku'] == true,
    );
  }

  final bool pipAvailable;
  final bool pipAutoOnLeaveSupported;
  final bool pipCanHideDanmaku;
}
