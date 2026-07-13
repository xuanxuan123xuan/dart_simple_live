// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

const double systemBrightness = 0.5;

late StreamController<double> screenBrightnessController;

late StreamController<double> systemScreenBrightnessController;

class MockScreenBrightnessPlatform
    with MockPlatformInterfaceMixin
    implements ScreenBrightnessPlatform {
  double _systemBrightness = systemBrightness;
  double _currentBrightness = systemBrightness;
  double? _changedBrightness;

  bool _isAutoReset = true;
  bool _isAnimate = true;
  final _canChangeSystemBrightness = true;

  @override
  Future<double> get system => Future.value(_systemBrightness);

  @override
  Future<double> get application => Future.value(_currentBrightness);

  @override
  Future<void> setSystemScreenBrightness(double brightness) async {
    _systemBrightness = brightness;
  }

  @override
  Future<void> setApplicationScreenBrightness(double brightness,
      {bool animated = true}) async {
    _currentBrightness = brightness;
    _changedBrightness = brightness;
  }

  @override
  Future<void> resetApplicationScreenBrightness() async {
    _currentBrightness = systemBrightness;
    _changedBrightness = null;
  }

  @override
  Stream<double> get onSystemScreenBrightnessChanged =>
      systemScreenBrightnessController.stream;

  @override
  Stream<double> get onApplicationScreenBrightnessChanged =>
      screenBrightnessController.stream;

  @override
  Future<bool> get hasApplicationScreenBrightnessChanged async =>
      _changedBrightness != null;

  @override
  Future<bool> get isAutoReset async => _isAutoReset;

  @override
  Future<void> setAutoReset(bool isAutoReset) async {
    _isAutoReset = isAutoReset;
  }

  @override
  Future<bool> get isAnimate async => _isAnimate;

  @override
  Future<void> setAnimate(bool isAnimate) async {
    _isAnimate = isAnimate;
  }

  @override
  Future<bool> get canChangeSystemBrightness async =>
      _canChangeSystemBrightness;
}

void main() {
  late ScreenBrightness screenBrightness;
  late MockScreenBrightnessPlatform mockScreenBrightnessPlatform;

  setUp(() {
    mockScreenBrightnessPlatform = MockScreenBrightnessPlatform();
    ScreenBrightnessPlatform.instance = mockScreenBrightnessPlatform;
    screenBrightness = ScreenBrightness.instance;
  });

  test('get system brightness', () async {
    expect(await screenBrightness.system, systemBrightness);
  });

  test('set system screen brightness with valid number', () async {
    const targetBrightness = 0.1;
    await screenBrightness.setSystemScreenBrightness(targetBrightness);
    expect(await screenBrightness.system, targetBrightness);
  });

  test('get current screen brightness', () async {
    expect(await screenBrightness.current, systemBrightness);
  });

  test('get application screen brightness', () async {
    expect(await screenBrightness.application, systemBrightness);
  });

  test('set screen brightness with valid number', () async {
    const targetBrightness = 0.1;
    await screenBrightness.setScreenBrightness(targetBrightness);
    expect(await screenBrightness.current, targetBrightness);
  });

  test('set application screen brightness with valid number', () async {
    const targetBrightness = 0.1;
    await screenBrightness.setApplicationScreenBrightness(targetBrightness);
    expect(await screenBrightness.application, targetBrightness);
  });

  test('reset screen brightness', () async {
    await screenBrightness.resetScreenBrightness();
    expect(await screenBrightness.current, systemBrightness);
  });

  test('reset application screen brightness', () async {
    await screenBrightness.resetApplicationScreenBrightness();
    expect(await screenBrightness.application, systemBrightness);
  });

  group('on screen brightness changed stream', () {
    setUp(() {
      screenBrightnessController = StreamController<double>();
    });

    tearDown(() {
      screenBrightnessController.close();
    });

    test('on screen brightness receive values', () async {
      final queue =
          StreamQueue<double>(screenBrightness.onCurrentBrightnessChanged);

      screenBrightnessController.add(0.2);
      expect(await queue.next, 0.2);

      screenBrightnessController.add(systemBrightness);
      expect(await queue.next, systemBrightness);

      screenBrightnessController.add(0);
      expect(await queue.next, 0);

      screenBrightnessController.add(1);
      expect(await queue.next, 1);
    });
  });

  group('on application screen brightness changed stream', () {
    setUp(() {
      screenBrightnessController = StreamController<double>();
    });

    tearDown(() {
      screenBrightnessController.close();
    });

    test('on application screen brightness receive values', () async {
      final queue = StreamQueue<double>(
          screenBrightness.onApplicationScreenBrightnessChanged);

      screenBrightnessController.add(0.2);
      expect(await queue.next, 0.2);

      screenBrightnessController.add(systemBrightness);
      expect(await queue.next, systemBrightness);

      screenBrightnessController.add(0);
      expect(await queue.next, 0);

      screenBrightnessController.add(1);
      expect(await queue.next, 1);
    });
  });

  group('on system screen brightness changed stream', () {
    setUp(() {
      systemScreenBrightnessController = StreamController<double>();
    });

    tearDown(() {
      systemScreenBrightnessController.close();
    });

    test('on system screen brightness receive values', () async {
      final queue =
          StreamQueue<double>(screenBrightness.onSystemScreenBrightnessChanged);

      systemScreenBrightnessController.add(0.2);
      expect(await queue.next, 0.2);

      systemScreenBrightnessController.add(systemBrightness);
      expect(await queue.next, systemBrightness);

      systemScreenBrightnessController.add(0);
      expect(await queue.next, 0);

      systemScreenBrightnessController.add(1);
      expect(await queue.next, 1);
    });
  });

  test('has screen brightness changed', () async {
    expect(await screenBrightness.hasChanged, false);

    await screenBrightness.setScreenBrightness(0.1);
    expect(await screenBrightness.hasChanged, true);

    await screenBrightness.setScreenBrightness(systemBrightness);
    expect(await screenBrightness.hasChanged, true);

    await screenBrightness.resetScreenBrightness();
    expect(await screenBrightness.hasChanged, false);
  });

  test('has application screen brightness changed', () async {
    expect(await screenBrightness.hasApplicationScreenBrightnessChanged, false);

    await screenBrightness.setApplicationScreenBrightness(0.1);
    expect(await screenBrightness.hasApplicationScreenBrightnessChanged, true);

    await screenBrightness.setApplicationScreenBrightness(systemBrightness);
    expect(await screenBrightness.hasApplicationScreenBrightnessChanged, true);

    await screenBrightness.resetApplicationScreenBrightness();
    expect(await screenBrightness.hasApplicationScreenBrightnessChanged, false);
  });

  test('is auto reset', () async {
    expect(await screenBrightness.isAutoReset, true);

    await screenBrightness.setAutoReset(false);
    expect(await screenBrightness.isAutoReset, false);

    await screenBrightness.setAutoReset(true);
    expect(await screenBrightness.isAutoReset, true);
  });

  test('is animate', () async {
    expect(await screenBrightness.isAnimate, true);

    await screenBrightness.setAnimate(false);
    expect(await screenBrightness.isAnimate, false);

    await screenBrightness.setAnimate(true);
    expect(await screenBrightness.isAnimate, true);
  });

  test('can change system brightness', () async {
    expect(await screenBrightness.canChangeSystemBrightness, true);
  });
}
