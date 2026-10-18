import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_controller.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_page.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class _TestSettingsController extends AppSettingsController {
  @override
  // Keep these tests independent from Hive-backed app startup.
  // ignore: must_call_super
  void onInit() {}
}

class _MemoryStorageService extends LocalStorageService {
  final Map<dynamic, dynamic> values = {};

  @override
  T getValue<T>(dynamic key, T defaultValue) {
    final value = values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    values[key] = value;
  }
}

void main() {
  late Directory hiveDirectory;
  late Box settingsBox;
  late AppSettingsController settings;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'simple_live_platform_visibility_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    Get.testMode = true;
    settingsBox = await Hive.openBox(
      'settings_${DateTime.now().microsecondsSinceEpoch}',
    );
    Get.put<LocalStorageService>(
      LocalStorageService()..settingsBox = settingsBox,
    );
    settings = Get.put<AppSettingsController>(_TestSettingsController());
    settings.siteSort.assignAll(Sites.allSites.keys);
    settings.hiddenSiteIds.clear();
    settings.homeSort.assignAll(Constant.allHomePages.keys);
    Get.put(IndexedSettingsController());
  });

  tearDown(() async {
    await settingsBox.deleteFromDisk();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('normalizes stored order and hidden ids while keeping new sites visible',
      () async {
    await settingsBox.put(LocalStorageService.kSiteSort, ' huya,huya,retired ');
    await settingsBox.put(
      LocalStorageService.kHiddenSiteIds,
      ' bilibili,huya,retired,huya, ,',
    );

    settings.initSiteSort();
    settings.initHiddenSiteIds();

    expect(settings.siteSort, [
      Constant.kHuya,
      Constant.kBiliBili,
      Constant.kDouyu,
      Constant.kDouyin,
      Constant.kKuaishou,
      Constant.kXiaohongshu,
    ]);
    expect(settings.hiddenSiteIds, {Constant.kBiliBili, Constant.kHuya});
    expect(
      Sites.visibleSites.map((site) => site.id),
      [
        Constant.kDouyu,
        Constant.kDouyin,
        Constant.kKuaishou,
        Constant.kXiaohongshu,
      ],
    );
    expect(Sites.supportSites, hasLength(Sites.allSites.length));
  });

  test('repairs all-hidden settings and rejects hiding the last visible site',
      () async {
    final order = [
      Constant.kDouyu,
      Constant.kBiliBili,
      Constant.kHuya,
      Constant.kDouyin,
      Constant.kKuaishou,
      Constant.kXiaohongshu,
    ];
    await settingsBox.put(LocalStorageService.kSiteSort, order.join(','));
    await settingsBox.put(
      LocalStorageService.kHiddenSiteIds,
      '${order.join(',')},retired',
    );

    settings.initSiteSort();
    settings.initHiddenSiteIds();

    expect(settings.hiddenSiteIds, order.skip(1).toSet());
    expect(Sites.visibleSites.map((site) => site.id), [Constant.kDouyu]);
    expect(settings.setSiteVisible(Constant.kDouyu, false), isFalse);
    expect(settings.setSiteVisible(' retired ', false), isFalse);
    expect(settings.setSiteVisible(' ${Constant.kBiliBili} ', true), isTrue);
    expect(settings.visibleSiteCount, 2);
    await Future<void>.delayed(Duration.zero);
    expect(
      settingsBox.get(LocalStorageService.kHiddenSiteIds),
      order.skip(2).join(','),
    );
  });

  test('visibility changes publish only the final visible snapshot', () {
    _useMemoryStorage();
    settings.setSiteVisible(Constant.kHuya, false);
    final snapshots = <List<String>>[];
    final worker = ever(settings.hiddenSiteIds, (_) {
      snapshots.add(Sites.visibleSites.map((site) => site.id).toList());
    });
    addTearDown(worker.dispose);

    settings.setSiteVisible(Constant.kDouyu, false);

    expect(snapshots, [
      [
        Constant.kBiliBili,
        Constant.kDouyin,
        Constant.kKuaishou,
        Constant.kXiaohongshu,
      ],
    ]);
  });

  test('persists order and visibility across closing and reopening Hive',
      () async {
    settings.setSiteSort(settings.siteSort.reversed.toList());
    settings.setSiteVisible(Constant.kDouyu, false);
    await settingsBox.flush();
    final name = settingsBox.name;
    await settingsBox.close();
    settingsBox = await Hive.openBox(name);
    LocalStorageService.instance.settingsBox = settingsBox;
    final restarted = _TestSettingsController();
    restarted.initSiteSort();
    restarted.initHiddenSiteIds();

    expect(restarted.siteSort, Sites.allSites.keys.toList().reversed.toList());
    expect(restarted.hiddenSiteIds, {Constant.kDouyu});
  });

  testWidgets('shows all platforms and prevents hiding the last visible one',
      (tester) async {
    final memoryStorage = _useMemoryStorage();
    for (final siteId in settings.siteSort.skip(1)) {
      expect(settings.setSiteVisible(siteId, false), isTrue);
    }

    await _pumpSettingsPage(tester);

    final visibleSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey('platform-visibility-bilibili')),
    );
    expect(visibleSwitch.value, isTrue);
    expect(visibleSwitch.onChanged, isNull);
    expect(find.text('至少保留一个平台显示'), findsOneWidget);
    expect(find.text('平台显示与排序'), findsOneWidget);
    expect(find.byType(ReorderableListView).last, findsOneWidget);
    expect(
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView).last)
          .buildDefaultDragHandles,
      isFalse,
    );

    final hiddenSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey('platform-visibility-douyu')),
    );
    expect(hiddenSwitch.value, isFalse);
    expect(hiddenSwitch.onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('platform-visibility-douyu')));
    await tester.pumpAndSettle();

    expect(settings.isSiteVisible(Constant.kDouyu), isTrue);
    expect(
      memoryStorage.values[LocalStorageService.kHiddenSiteIds],
      settings.siteSort.skip(2).join(','),
    );
  });

  testWidgets('mouse drag handle reorders platforms', (tester) async {
    final storage = _useMemoryStorage();
    final initialFirst = settings.siteSort.first;
    settings.setSiteVisible(initialFirst, false);
    await _pumpSettingsPage(tester);

    final handle = find.descendant(
      of: find.byKey(ValueKey(initialFirst)),
      matching: find.byIcon(Icons.drag_handle),
    );
    final target = find.byKey(ValueKey(settings.siteSort[2]));
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(settings.siteSort.first, isNot(initialFirst));
    expect(settings.hiddenSiteIds, {initialFirst});
    expect(settings.siteSort, contains(initialFirst));
    expect(
      storage.values[LocalStorageService.kSiteSort],
      settings.siteSort.join(','),
    );
  });

  testWidgets('touch long press on a platform row reorders platforms',
      (tester) async {
    _useMemoryStorage();
    await _pumpSettingsPage(tester, size: const Size(390, 1500));

    final initialFirst = settings.siteSort.first;
    final firstRow = find.byKey(ValueKey(initialFirst));
    final target = find.byKey(ValueKey(settings.siteSort[2]));
    final gesture = await tester.startGesture(
      tester.getTopLeft(firstRow) + const Offset(80, 24),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(settings.siteSort.first, isNot(initialFirst));
  });
}

Future<void> _pumpSettingsPage(WidgetTester tester,
    {Size size = const Size(900, 1500)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const GetMaterialApp(home: IndexedSettingsPage()),
  );
  await tester.pumpAndSettle();
}

_MemoryStorageService _useMemoryStorage() {
  Get.delete<LocalStorageService>(force: true);
  final storage = _MemoryStorageService();
  Get.put<LocalStorageService>(storage);
  return storage;
}
