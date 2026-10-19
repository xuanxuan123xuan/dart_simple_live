import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/modules/settings/danmaku_display_settings.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/widgets/tv_danmaku_display_settings.dart';

class _QuietLocalStorageService extends LocalStorageService {
  @override
  T getValue<T>(dynamic key, T defaultValue) {
    try {
      return settingsBox.get(key, defaultValue: defaultValue) as T;
    } catch (_) {
      return defaultValue;
    }
  }

  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    await settingsBox.put(key, value);
  }
}

class _WidgetAppSettingsController extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void setDanmuDisplayMode(String value) {
    danmuDisplayMode.value = DanmakuDisplaySettings.normalizeMode(value);
  }

  @override
  void setDanmuMaxLines(int value) {
    danmuMaxLines.value = DanmakuDisplaySettings.normalizeMaxLines(value);
  }

  @override
  void setDanmuArea(double value) {
    danmuArea.value = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  late LocalStorageService storage;
  late AppSettingsController settings;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'tv_danmaku_display_settings_',
    );
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    Get.reset();
    storage = Get.put(_QuietLocalStorageService());
    await storage.init();
    await storage.settingsBox.clear();
    await storage.shieldBox.clear();
    settings = Get.put(AppSettingsController());
  });

  tearDown(() async {
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('defaults new settings for existing installs and preserves old area',
      () async {
    await storage.setValue(LocalStorageService.kDanmuArea, 0.75);
    expect(
      storage.settingsBox.containsKey(LocalStorageService.kDanmuDisplayMode),
      isFalse,
    );
    expect(
      storage.settingsBox.containsKey(LocalStorageService.kDanmuMaxLines),
      isFalse,
    );

    Get.delete<AppSettingsController>(force: true);
    final restored = Get.put(AppSettingsController());

    expect(restored.danmuDisplayMode.value, DanmakuDisplaySettings.areaMode);
    expect(
        restored.danmuMaxLines.value, DanmakuDisplaySettings.defaultMaxLines);
    expect(restored.effectiveDanmuMaxLines, 0);
    expect(restored.danmuArea.value, 0.75);
  });

  test('persists mode, line count, and area independently across restart',
      () async {
    settings.setDanmuDisplayMode(DanmakuDisplaySettings.linesMode);
    settings.setDanmuMaxLines(6);
    settings.setDanmuArea(0.75);
    await storage.settingsBox.flush();

    Get.delete<AppSettingsController>(force: true);
    final restored = Get.put(AppSettingsController());

    expect(restored.danmuDisplayMode.value, DanmakuDisplaySettings.linesMode);
    expect(restored.danmuMaxLines.value, 6);
    expect(restored.effectiveDanmuMaxLines, 6);
    expect(restored.danmuArea.value, 0.75);

    restored.setDanmuDisplayMode(DanmakuDisplaySettings.areaMode);
    expect(restored.effectiveDanmuMaxLines, 0);
    expect(restored.danmuMaxLines.value, 6);
    expect(restored.danmuArea.value, 0.75);
  });

  test('normalizes invalid persisted values to area mode and three lines',
      () async {
    await storage.setValue(LocalStorageService.kDanmuDisplayMode, 'invalid');
    await storage.setValue(LocalStorageService.kDanmuMaxLines, 7);

    Get.delete<AppSettingsController>(force: true);
    final restored = Get.put(AppSettingsController());

    expect(restored.danmuDisplayMode.value, DanmakuDisplaySettings.areaMode);
    expect(
        restored.danmuMaxLines.value, DanmakuDisplaySettings.defaultMaxLines);
    expect(restored.effectiveDanmuMaxLines, 0);
  });

  test('normalizes persisted values with the wrong storage types', () async {
    await storage.setValue(LocalStorageService.kDanmuDisplayMode, 1);
    await storage.setValue(LocalStorageService.kDanmuMaxLines, '5');

    Get.delete<AppSettingsController>(force: true);
    final restored = Get.put(AppSettingsController());

    expect(restored.danmuDisplayMode.value, DanmakuDisplaySettings.areaMode);
    expect(
        restored.danmuMaxLines.value, DanmakuDisplaySettings.defaultMaxLines);
    expect(restored.effectiveDanmuMaxLines, 0);
  });

  test('normalizes invalid setter values before storing them', () async {
    settings.setDanmuDisplayMode('unsupported');
    settings.setDanmuMaxLines(0);
    await storage.settingsBox.flush();

    expect(settings.danmuDisplayMode.value, DanmakuDisplaySettings.areaMode);
    expect(
        settings.danmuMaxLines.value, DanmakuDisplaySettings.defaultMaxLines);
    expect(
      storage.getValue(LocalStorageService.kDanmuDisplayMode, ''),
      DanmakuDisplaySettings.areaMode,
    );
    expect(
      storage.getValue(LocalStorageService.kDanmuMaxLines, 0),
      DanmakuDisplaySettings.defaultMaxLines,
    );
  });

  testWidgets('remote focus stays on the same rows as mode changes', (
    tester,
  ) async {
    Get.delete<AppSettingsController>(force: true);
    settings = Get.put<AppSettingsController>(_WidgetAppSettingsController());
    final modeFocusNode = AppFocusNode();
    final valueFocusNode = AppFocusNode();
    addTearDown(() {
      modeFocusNode.dispose();
      valueFocusNode.dispose();
    });

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1920, 1080),
        builder: (_, child) => GetMaterialApp(
          home: Scaffold(
            body: TvDanmakuDisplaySettings(
              modeFocusNode: modeFocusNode,
              valueFocusNode: valueFocusNode,
            ),
          ),
        ),
      ),
    );
    modeFocusNode.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(settings.danmuDisplayMode.value, DanmakuDisplaySettings.linesMode);
    expect(find.text('最多行数'), findsOneWidget);
    expect(modeFocusNode.hasFocus, isTrue);

    valueFocusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(settings.danmuMaxLines.value, 4);
    expect(valueFocusNode.hasFocus, isTrue);

    modeFocusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(settings.danmuDisplayMode.value, DanmakuDisplaySettings.areaMode);
    expect(find.text('显示区域'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(settings.danmuArea.value, 0.25);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('remote dialog selection and back restore row focus', (
    tester,
  ) async {
    Get.delete<AppSettingsController>(force: true);
    settings = Get.put<AppSettingsController>(_WidgetAppSettingsController());
    final modeFocusNode = AppFocusNode();
    final valueFocusNode = AppFocusNode();
    addTearDown(() {
      modeFocusNode.dispose();
      valueFocusNode.dispose();
    });

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1920, 1080),
        builder: (_, child) => GetMaterialApp(
          home: Scaffold(
            body: TvDanmakuDisplaySettings(
              modeFocusNode: modeFocusNode,
              valueFocusNode: valueFocusNode,
            ),
          ),
        ),
      ),
    );
    modeFocusNode.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(settings.danmuDisplayMode.value, DanmakuDisplaySettings.linesMode);
    expect(modeFocusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(valueFocusNode.hasFocus, isTrue);
    expect(find.text('最多行数'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(valueFocusNode.hasFocus, isTrue);
    expect(
        settings.danmuMaxLines.value, DanmakuDisplaySettings.defaultMaxLines);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
