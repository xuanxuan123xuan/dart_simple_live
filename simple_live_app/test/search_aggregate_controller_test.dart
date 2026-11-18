import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_aggregate_controller.dart';
import 'package:simple_live_app/modules/search/search_aggregate_models.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('keeps successful platform results when another platform times out',
      () async {
    final neverCompletes = Completer<LiveSearchRoomResult>();
    final slowSite = _FakeLiveSite(rooms: (_, __) => neverCompletes.future);
    final controller = SearchAggregateController(
      sites: <Site>[
        _site(
          'success',
          _FakeLiveSite(
            rooms: (_, __) => Future<LiveSearchRoomResult>.value(
              LiveSearchRoomResult(
                hasMore: false,
                items: <LiveRoomItem>[
                  LiveRoomItem(
                    roomId: '1',
                    title: 'title',
                    cover: 'cover',
                    userName: 'user',
                  ),
                ],
              ),
            ),
          ),
        ),
        _site(
          'slow',
          slowSite,
        ),
      ],
      timeout: Duration.zero,
    );

    await controller.search('keyword', 0);

    expect(
      controller.result.value.sites[0].status,
      SearchAggregateSiteStatus.success,
    );
    expect(controller.result.value.sites[0].items, hasLength(1));
    expect(
      controller.result.value.sites[1].status,
      SearchAggregateSiteStatus.error,
    );
    expect(controller.result.value.sites[1].error, isA<TimeoutException>());
    expect(slowSite.cancellations.single?.isCancelled, isTrue);

    neverCompletes.complete(
      LiveSearchRoomResult(hasMore: false, items: <LiveRoomItem>[]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.result.value.sites[1].error,
      isA<TimeoutException>(),
    );
    controller.onClose();
  });

  test('cancels an in-flight search when the controller closes', () async {
    final pending = Completer<LiveSearchRoomResult>();
    final fake = _FakeLiveSite(rooms: (_, __) => pending.future);
    final controller = SearchAggregateController(
      sites: <Site>[_site('site', fake)],
      timeout: const Duration(seconds: 1),
    );

    final search = controller.search('keyword', 0);
    await Future<void>.delayed(Duration.zero);
    controller.onClose();

    expect(fake.cancellations.single?.isCancelled, isTrue);
    pending.complete(
      LiveSearchRoomResult(hasMore: false, items: <LiveRoomItem>[]),
    );
    await search;
  });

  test('deduplicates an identical in-flight search', () async {
    final pending = Completer<LiveSearchRoomResult>();
    final fake = _FakeLiveSite(rooms: (_, __) => pending.future);
    final controller = SearchAggregateController(
      sites: <Site>[_site('site', fake)],
      timeout: const Duration(seconds: 1),
    );

    final first = controller.search('keyword', 0);
    await Future<void>.delayed(Duration.zero);
    await controller.search(' keyword ', 0);

    expect(fake.roomCalls, 1);
    expect(fake.cancellations.single?.isCancelled, isFalse);
    pending.complete(
      LiveSearchRoomResult(hasMore: false, items: <LiveRoomItem>[]),
    );
    await first;
    controller.onClose();
  });

  test('ignores a late result from an older keyword', () async {
    final oldResult = Completer<LiveSearchRoomResult>();
    late _FakeLiveSite fake;
    final controller = SearchAggregateController(
      sites: <Site>[
        _site(
          'site',
          fake = _FakeLiveSite(
            rooms: (keyword, _) {
              if (keyword == 'old') {
                return oldResult.future;
              }
              return Future<LiveSearchRoomResult>.value(
                LiveSearchRoomResult(
                  hasMore: false,
                  items: <LiveRoomItem>[
                    LiveRoomItem(
                      roomId: 'new',
                      title: 'new title',
                      cover: 'cover',
                      userName: 'new user',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
      timeout: const Duration(seconds: 1),
    );

    final firstSearch = controller.search('old', 0);
    await controller.search('new', 0);
    expect(fake.cancellations.first?.isCancelled, isTrue);
    oldResult.complete(
      LiveSearchRoomResult(
        hasMore: false,
        items: <LiveRoomItem>[
          LiveRoomItem(
            roomId: 'old',
            title: 'old title',
            cover: 'cover',
            userName: 'old user',
          ),
        ],
      ),
    );
    await firstSearch;

    expect(controller.result.value.query?.keyword, 'new');
    expect(
        controller.result.value.sites.single.items.single, isA<LiveRoomItem>());
    expect(
      (controller.result.value.sites.single.items.single as LiveRoomItem)
          .roomId,
      'new',
    );
    controller.onClose();
  });
}

Site _site(String id, LiveSite liveSite) {
  return Site(id: id, name: id, logo: '', liveSite: liveSite);
}

class _FakeLiveSite extends LiveSite {
  _FakeLiveSite({required this.rooms});

  final Future<LiveSearchRoomResult> Function(String keyword, int page) rooms;
  final List<CoreCancellation?> cancellations = <CoreCancellation?>[];
  int roomCalls = 0;

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) {
    roomCalls++;
    cancellations.add(cancellation);
    return rooms(keyword, page);
  }
}
