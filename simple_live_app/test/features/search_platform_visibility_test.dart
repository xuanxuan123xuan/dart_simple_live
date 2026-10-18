import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_aggregate_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  late Directory hiveDirectory;
  late Map<String, Site> originalSites;
  late AppSettingsController settings;

  setUp(() async {
    originalSites = Map<String, Site>.of(Sites.allSites);
    hiveDirectory = await Directory.systemTemp.createTemp(
      'simple_live_search_visibility_',
    );
    Hive.init(hiveDirectory.path);
    Get.put<LocalStorageService>(LocalStorageService());
    await LocalStorageService.instance.init();
    settings = Get.put<AppSettingsController>(AppSettingsController());
  });

  tearDown(() async {
    Sites.allSites
      ..clear()
      ..addAll(originalSites);
    Get.reset();
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('search follows visible order and ignores hidden-only changes',
      () async {
    final first = _FakeLiveSite();
    final hidden = _FakeLiveSite();
    final last = _FakeLiveSite();
    _registerSite('visibility_first', first);
    _registerSite('visibility_hidden', hidden);
    _registerSite('visibility_last', last);
    settings.siteSort.assignAll(
      ['visibility_first', 'visibility_hidden', 'visibility_last'],
    );
    settings.hiddenSiteIds.add('visibility_hidden');

    final controller = Get.put<SearchAggregateController>(
      SearchAggregateController(timeout: const Duration(seconds: 2)),
    );

    await controller.search('needle', 0);
    expect(_resultSiteIds(controller), ['visibility_first', 'visibility_last']);
    expect(first.roomKeywords, ['needle']);
    expect(hidden.roomKeywords, isEmpty);
    expect(last.roomKeywords, ['needle']);

    settings.siteSort.assignAll(
      ['visibility_first', 'visibility_last', 'visibility_hidden'],
    );
    await _settle();
    expect(first.roomKeywords, ['needle']);
    expect(hidden.roomKeywords, isEmpty);
    expect(last.roomKeywords, ['needle']);

    settings.siteSort.assignAll(
      ['visibility_last', 'visibility_first', 'visibility_hidden'],
    );
    await _settle();
    expect(first.roomKeywords, ['needle', 'needle']);
    expect(last.roomKeywords, ['needle', 'needle']);
    expect(
      _resultSiteIds(controller),
      ['visibility_last', 'visibility_first'],
    );

    settings.hiddenSiteIds.remove('visibility_hidden');
    await _settle();
    expect(hidden.roomKeywords, ['needle']);
    expect(
      _resultSiteIds(controller),
      ['visibility_last', 'visibility_first', 'visibility_hidden'],
    );

    await controller.search('   ', 0);
    final callsBeforeBlankConfigurationChange = <int>[
      first.roomKeywords.length,
      hidden.roomKeywords.length,
      last.roomKeywords.length,
    ];
    settings.hiddenSiteIds.add('visibility_first');
    settings.siteSort.assignAll(
      ['visibility_first', 'visibility_last', 'visibility_hidden'],
    );
    await _settle();
    expect(controller.result.value.query, isNull);
    expect(
      <int>[
        first.roomKeywords.length,
        hidden.roomKeywords.length,
        last.roomKeywords.length,
      ],
      callsBeforeBlankConfigurationChange,
    );

    await Get.delete<SearchAggregateController>(force: true);
    settings.hiddenSiteIds.remove('visibility_first');
    await _settle();
    expect(
      <int>[
        first.roomKeywords.length,
        hidden.roomKeywords.length,
        last.roomKeywords.length,
      ],
      callsBeforeBlankConfigurationChange,
    );
  });

  test('ignores a late completion after settings restart the query', () async {
    final oldResult = Completer<LiveSearchRoomResult>();
    final first = _FakeLiveSite(
      rooms: (_, call) => call == 0
          ? oldResult.future
          : Future<LiveSearchRoomResult>.value(_rooms('first-new')),
    );
    final last = _FakeLiveSite();
    _registerSite('visibility_first', first);
    _registerSite('visibility_last', last);
    settings.siteSort.assignAll(['visibility_first', 'visibility_last']);

    final controller = Get.put<SearchAggregateController>(
      SearchAggregateController(timeout: const Duration(seconds: 3)),
    );
    final originalSearch = controller.search('needle', 0);
    expect(first.roomKeywords, ['needle']);
    expect(last.roomKeywords, ['needle']);

    settings.siteSort.assignAll(['visibility_last', 'visibility_first']);
    await _settle();
    expect(first.roomKeywords, ['needle', 'needle']);
    expect(last.roomKeywords, ['needle', 'needle']);
    expect(first.cancellations.first?.isCancelled, isTrue);
    expect(
      _resultSiteIds(controller),
      ['visibility_last', 'visibility_first'],
    );
    expect(_roomIds(controller), ['visibility_last', 'first-new']);

    oldResult.complete(_rooms('first-old'));
    await originalSearch;
    expect(
      _resultSiteIds(controller),
      ['visibility_last', 'visibility_first'],
    );
    expect(_roomIds(controller), ['visibility_last', 'first-new']);

    await Get.delete<SearchAggregateController>(force: true);
  });

  test('does not start a queued settings refresh after onClose', () async {
    final first = _FakeLiveSite();
    final last = _FakeLiveSite();
    _registerSite('visibility_first', first);
    _registerSite('visibility_last', last);
    settings.siteSort.assignAll(['visibility_first', 'visibility_last']);

    final controller = Get.put<SearchAggregateController>(
      SearchAggregateController(timeout: const Duration(seconds: 2)),
    );
    await controller.search('needle', 0);
    final originalCallCounts = <int>[
      first.roomKeywords.length,
      last.roomKeywords.length
    ];

    settings.siteSort.assignAll(['visibility_last', 'visibility_first']);
    controller.onClose();
    await _settle();

    expect(
      <int>[first.roomKeywords.length, last.roomKeywords.length],
      originalCallCounts,
    );
    await Get.delete<SearchAggregateController>(force: true);
  });
}

void _registerSite(String id, _FakeLiveSite liveSite) {
  Sites.allSites[id] = Site(id: id, name: id, logo: '', liveSite: liveSite);
}

List<String> _resultSiteIds(SearchAggregateController controller) =>
    controller.result.value.sites.map((site) => site.site.id).toList();

List<String> _roomIds(SearchAggregateController controller) =>
    controller.result.value.sites
        .map((site) => (site.items.single as LiveRoomItem).roomId)
        .toList();

Future<void> _settle() async {
  for (var iteration = 0; iteration < 5; iteration++) {
    await Future<void>.delayed(Duration.zero);
  }
}

LiveSearchRoomResult _rooms(String roomId) => LiveSearchRoomResult(
      hasMore: false,
      items: <LiveRoomItem>[
        LiveRoomItem(
          roomId: roomId,
          title: roomId,
          cover: '',
          userName: roomId,
        ),
      ],
    );

class _FakeLiveSite extends LiveSite {
  _FakeLiveSite({this.rooms});

  final Future<LiveSearchRoomResult> Function(String keyword, int call)? rooms;
  final List<String> roomKeywords = <String>[];
  final List<CoreCancellation?> cancellations = <CoreCancellation?>[];

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) {
    final call = roomKeywords.length;
    roomKeywords.add(keyword);
    cancellations.add(cancellation);
    return rooms?.call(keyword, call) ??
        Future<LiveSearchRoomResult>.value(_rooms('visibility_last'));
  }
}
