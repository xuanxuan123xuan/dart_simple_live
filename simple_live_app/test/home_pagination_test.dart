import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('paged views auto-load near the end without a persistent button', () {
    for (final path in <String>[
      'lib/widgets/page_grid_view.dart',
      'lib/widgets/page_list_view.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('notification.metrics.extentAfter < 280'));
      expect(source, isNot(contains('const Text("加载更多")')));
    }
  });

  test('home hides load more when the platform reports no next page', () async {
    final liveSite = _FakeLiveSite(<LiveCategoryResult>[
      LiveCategoryResult(
        hasMore: false,
        items: <LiveRoomItem>[_room('1')],
      ),
    ]);
    final controller = HomeListController(_site(liveSite));

    await controller.loadData();

    expect(controller.list, hasLength(1));
    expect(controller.canLoadMore.value, isFalse);
    await controller.loadData();
    expect(liveSite.requestedPages, <int>[1]);
  });

  test('home keeps loading until the platform reports the last page', () async {
    final liveSite = _FakeLiveSite(<LiveCategoryResult>[
      LiveCategoryResult(
        hasMore: true,
        items: <LiveRoomItem>[_room('1')],
      ),
      LiveCategoryResult(
        hasMore: false,
        items: <LiveRoomItem>[_room('2')],
      ),
    ]);
    final controller = HomeListController(_site(liveSite));

    await controller.loadData();
    expect(controller.canLoadMore.value, isTrue);
    await controller.loadData();

    expect(controller.list.map((item) => item.roomId), <String>['1', '2']);
    expect(controller.canLoadMore.value, isFalse);
    expect(liveSite.requestedPages, <int>[1, 2]);
  });
}

Site _site(LiveSite liveSite) {
  return Site(
    id: 'fake',
    name: 'Fake',
    logo: '',
    liveSite: liveSite,
  );
}

LiveRoomItem _room(String id) {
  return LiveRoomItem(
    roomId: id,
    title: 'Room $id',
    cover: '',
    userName: 'User $id',
  );
}

class _FakeLiveSite extends LiveSite {
  _FakeLiveSite(this.responses);

  final List<LiveCategoryResult> responses;
  final List<int> requestedPages = <int>[];

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    requestedPages.add(page);
    return responses[page - 1];
  }
}
