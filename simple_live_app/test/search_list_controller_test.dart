import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('ignores a late result from an older keyword', () async {
    final oldResult = Completer<LiveSearchRoomResult>();
    final fake = _FakeLiveSite(
      rooms: (keyword, page) {
        if (keyword == 'old') return oldResult.future;
        return Future<LiveSearchRoomResult>.value(
          _rooms('new'),
        );
      },
    );
    final controller = _putController(fake, 'late-keyword');

    try {
      final oldSearch = controller.search(query: 'old');
      await controller.search(query: 'new');

      expect(fake.cancellations.first?.isCancelled, isTrue);
      expect(_roomIds(controller), ['new']);

      oldResult.complete(_rooms('old'));
      await oldSearch;

      expect(_roomIds(controller), ['new']);
    } finally {
      await Get.delete<SearchListController>(
        tag: 'late-keyword',
        force: true,
      );
    }
  });

  test('does not mix a pending room request into anchor mode', () async {
    final pendingRooms = Completer<LiveSearchRoomResult>();
    final fake = _FakeLiveSite(
      rooms: (_, __) => pendingRooms.future,
      anchors: (_, __) => Future<LiveSearchAnchorResult>.value(
        _anchors('anchor'),
      ),
    );
    final controller = _putController(fake, 'mode-switch');

    try {
      final roomSearch = controller.search(query: 'keyword', mode: 0);
      await controller.search(query: 'keyword', mode: 1);

      expect(fake.cancellations.first?.isCancelled, isTrue);
      expect(fake.calls, [
        const _SearchCall.rooms('keyword', 1),
        const _SearchCall.anchors('keyword', 1),
      ]);
      expect(controller.list, hasLength(1));
      expect(controller.list.single, isA<LiveAnchorItem>());

      pendingRooms.complete(_rooms('room'));
      await roomSearch;

      expect(controller.list, hasLength(1));
      expect(controller.list.single, isA<LiveAnchorItem>());
    } finally {
      await Get.delete<SearchListController>(
        tag: 'mode-switch',
        force: true,
      );
    }
  });

  test('loads the initial page and next page as 1 then 2', () async {
    final firstPageStarted = Completer<void>();
    final fake = _FakeLiveSite(
      rooms: (_, page) {
        if (page == 1 && !firstPageStarted.isCompleted) {
          firstPageStarted.complete();
        }
        return Future<LiveSearchRoomResult>.value(_rooms('page$page'));
      },
    );
    final controller = _putController(
      fake,
      'pagination',
      keyword: 'keyword',
    );

    try {
      await firstPageStarted.future;
      await Future<void>.delayed(Duration.zero);
      await controller.loadData();

      expect(fake.calls, [
        const _SearchCall.rooms('keyword', 1),
        const _SearchCall.rooms('keyword', 2),
      ]);
      expect(_roomIds(controller), ['page1', 'page2']);
    } finally {
      await Get.delete<SearchListController>(
        tag: 'pagination',
        force: true,
      );
    }
  });

  test('does not request when the keyword is empty', () async {
    final fake = _FakeLiveSite();
    final controller = _putController(
      fake,
      'empty-keyword',
      keyword: '   ',
    );

    try {
      await Future<void>.delayed(Duration.zero);
      await controller.search(query: '  ');

      expect(fake.calls, isEmpty);
      expect(controller.list, isEmpty);
    } finally {
      await Get.delete<SearchListController>(
        tag: 'empty-keyword',
        force: true,
      );
    }
  });

  test('stops pagination when the first page reports no more results',
      () async {
    final fake = _FakeLiveSite(
      rooms: (_, __) => Future<LiveSearchRoomResult>.value(
        LiveSearchRoomResult(
          hasMore: false,
          items: <LiveRoomItem>[
            LiveRoomItem(
              roomId: 'terminal',
              title: 'terminal',
              cover: '',
              userName: 'terminal',
            ),
          ],
        ),
      ),
    );
    final controller = _putController(fake, 'terminal-page');

    try {
      await controller.search(query: 'keyword');
      await controller.loadData();

      expect(controller.canLoadMore.value, isFalse);
      expect(fake.calls, [const _SearchCall.rooms('keyword', 1)]);
    } finally {
      await Get.delete<SearchListController>(
        tag: 'terminal-page',
        force: true,
      );
    }
  });

  test('does not request another page when continuation is unknown', () async {
    final fake = _FakeLiveSite(
      rooms: (_, __) => Future<LiveSearchRoomResult>.value(
        LiveSearchRoomResult(
          items: <LiveRoomItem>[
            LiveRoomItem(
              roomId: 'unknown',
              title: 'unknown',
              cover: '',
              userName: 'unknown',
            ),
          ],
          metadata: const LiveSearchMetadata(
            continuation: SearchContinuation.unknown,
          ),
        ),
      ),
    );
    final controller = _putController(fake, 'unknown-page');

    try {
      await controller.search(query: 'keyword');
      await controller.loadData();

      expect(controller.paginationUnavailable.value, isTrue);
      expect(controller.canLoadMore.value, isFalse);
      expect(fake.calls, [const _SearchCall.rooms('keyword', 1)]);
    } finally {
      await Get.delete<SearchListController>(
        tag: 'unknown-page',
        force: true,
      );
    }
  });

  test('cancels an in-flight request when the controller closes', () async {
    final pending = Completer<LiveSearchRoomResult>();
    final fake = _FakeLiveSite(rooms: (_, __) => pending.future);
    final controller = _putController(fake, 'close-cancellation');

    final search = controller.search(query: 'keyword');
    await Future<void>.delayed(Duration.zero);
    await Get.delete<SearchListController>(
      tag: 'close-cancellation',
      force: true,
    );

    expect(fake.cancellations.single?.isCancelled, isTrue);
    pending.complete(_rooms('late'));
    await search;
  });
}

SearchListController _putController(
  _FakeLiveSite fake,
  String tag, {
  String keyword = '',
}) {
  return Get.put<SearchListController>(
    SearchListController(
      Site(id: 'fake', name: 'fake', logo: '', liveSite: fake),
      keyword: keyword,
    ),
    tag: tag,
  );
}

List<String> _roomIds(SearchListController controller) {
  return controller.list.map((item) => (item as LiveRoomItem).roomId).toList();
}

LiveSearchRoomResult _rooms(String roomId) {
  return LiveSearchRoomResult(
    hasMore: roomId != 'page2',
    items: <LiveRoomItem>[
      LiveRoomItem(
        roomId: roomId,
        title: roomId,
        cover: '',
        userName: roomId,
      ),
    ],
  );
}

LiveSearchAnchorResult _anchors(String roomId) {
  return LiveSearchAnchorResult(
    hasMore: false,
    items: <LiveAnchorItem>[
      LiveAnchorItem(
        roomId: roomId,
        avatar: '',
        userName: roomId,
        liveStatus: true,
      ),
    ],
  );
}

class _FakeLiveSite extends LiveSite {
  _FakeLiveSite({this.rooms = _emptyRooms, this.anchors = _emptyAnchors});

  final Future<LiveSearchRoomResult> Function(String keyword, int page) rooms;
  final Future<LiveSearchAnchorResult> Function(String keyword, int page)
      anchors;
  final List<_SearchCall> calls = <_SearchCall>[];
  final List<CoreCancellation?> cancellations = <CoreCancellation?>[];

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) {
    calls.add(_SearchCall.rooms(keyword, page));
    cancellations.add(cancellation);
    return rooms(keyword, page);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) {
    calls.add(_SearchCall.anchors(keyword, page));
    cancellations.add(cancellation);
    return anchors(keyword, page);
  }
}

Future<LiveSearchRoomResult> _emptyRooms(String keyword, int page) {
  return Future<LiveSearchRoomResult>.value(
    LiveSearchRoomResult(hasMore: false, items: <LiveRoomItem>[]),
  );
}

Future<LiveSearchAnchorResult> _emptyAnchors(String keyword, int page) {
  return Future<LiveSearchAnchorResult>.value(
    LiveSearchAnchorResult(hasMore: false, items: <LiveAnchorItem>[]),
  );
}

class _SearchCall {
  const _SearchCall._(this.kind, this.keyword, this.page);

  const _SearchCall.rooms(String keyword, int page)
      : this._('rooms', keyword, page);
  const _SearchCall.anchors(String keyword, int page)
      : this._('anchors', keyword, page);

  final String kind;
  final String keyword;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is _SearchCall &&
        other.kind == kind &&
        other.keyword == keyword &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(kind, keyword, page);
}
