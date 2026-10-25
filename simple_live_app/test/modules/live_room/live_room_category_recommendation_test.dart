import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_category_recommendation.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  group('LiveRoomCategoryRecommendationState', () {
    test('merges concurrent lookups for the same request key', () async {
      final result = Completer<LiveSubCategory?>();
      final resolver = _FakeResolver((_) => result.future);
      final state = LiveRoomCategoryRecommendationState();
      final detail = _detail();
      final key = _key(detail);

      final first = state.prepare(
        key: key,
        detail: detail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      final second = state.prepare(
        key: key,
        detail: detail,
        resolver: resolver,
        isCurrent: (_) => true,
      );

      expect(identical(first, second), isTrue);
      expect(resolver.calls, 1);
      final category = _category('game');
      result.complete(category);
      expect(await first, same(category));
      expect(state.category, same(category));
      expect(state.status, LiveRoomCategoryResolutionStatus.available);
    });

    test('late result after a room change cannot replace current state',
        () async {
      final result = Completer<LiveSubCategory?>();
      final resolver = _FakeResolver((_) => result.future);
      final state = LiveRoomCategoryRecommendationState();
      final originalDetail = _detail(roomId: 'room-a');
      final originalKey = _key(originalDetail);
      final pending = state.prepare(
        key: originalKey,
        detail: originalDetail,
        resolver: resolver,
        isCurrent: (key) => key == originalKey,
      );

      final nextDetail = _detail(roomId: 'room-b');
      state.syncContext(_key(nextDetail), hasDetail: true);
      result.complete(_category('old-room-category'));

      expect(await pending, isNull);
      expect(state.category, isNull);
      expect(state.status, LiveRoomCategoryResolutionStatus.idle);
    });

    test('caches missing and unmatched tags but retries failures', () async {
      var failFirstAttempt = true;
      final resolver = _FakeResolver((detail) async {
        if (failFirstAttempt) {
          failFirstAttempt = false;
          throw StateError('temporary');
        }
        return null;
      });
      final state = LiveRoomCategoryRecommendationState();
      final detail = _detail();
      final key = _key(detail);

      final first = state.prepare(
        key: key,
        detail: detail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      expect(await first, isNull);
      expect(state.status, LiveRoomCategoryResolutionStatus.failed);

      await state.prepare(
        key: key,
        detail: detail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      expect(resolver.calls, 2);
      expect(state.status, LiveRoomCategoryResolutionStatus.unmatched);

      await state.prepare(
        key: key,
        detail: detail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      expect(resolver.calls, 2);

      final emptyDetail = _detail(
        categoryId: null,
        categoryName: null,
        categoryParentId: null,
        categoryParentName: null,
      );
      final emptyKey = _key(emptyDetail);
      await state.prepare(
        key: emptyKey,
        detail: emptyDetail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      expect(state.status, LiveRoomCategoryResolutionStatus.missingTags);
      expect(resolver.calls, 2);
    });

    test('context reads reject stale categories without mutating state', () async {
      var changes = 0;
      final state = LiveRoomCategoryRecommendationState(
        onChanged: () => changes++,
      );
      final original = _detail();
      final originalKey = _key(original);
      final category = _category('game');
      await state.prepare(
        key: originalKey,
        detail: original,
        resolver: _FakeResolver((_) async => category),
        isCurrent: (_) => true,
      );
      final changesBeforeRead = changes;
      final changedKey = _key(_detail(categoryName: 'Other'));
      expect(state.categoryFor(originalKey), same(category));
      expect(state.categoryFor(changedKey), isNull);
      expect(state.statusFor(changedKey, hasDetail: true),
          LiveRoomCategoryResolutionStatus.idle);
      expect(state.statusFor(originalKey, hasDetail: false),
          LiveRoomCategoryResolutionStatus.waitingForDetail);
      expect(changes, changesBeforeRead);
      expect(state.status, LiveRoomCategoryResolutionStatus.available);
    });

    test('generation changes and disposal discard pending completions', () async {
      final result = Completer<LiveSubCategory?>();
      final state = LiveRoomCategoryRecommendationState();
      final detail = _detail();
      final key = _key(detail);
      final pending = state.prepare(
        key: key,
        detail: detail,
        resolver: _FakeResolver((_) => result.future),
        isCurrent: (_) => true,
      );
      final nextKey = LiveRoomCategoryRequestKey.forRoom(
        loadGeneration: 2,
        platformId: 'test',
        roomId: detail.roomId,
        detail: detail,
      );
      state.syncContext(nextKey, hasDetail: false);
      state.invalidate();
      result.complete(_category('late'));
      expect(await pending, isNull);
      expect(state.categoryFor(nextKey), isNull);
      expect(state.status, LiveRoomCategoryResolutionStatus.waitingForDetail);
    });

    test('synchronous resolver failures can be retried', () async {
      final state = LiveRoomCategoryRecommendationState();
      final detail = _detail();
      var attempts = 0;
      final category = _category('retry');
      final resolver = _FakeResolver((_) {
        if (++attempts == 1) throw StateError('synchronous failure');
        return Future.value(category);
      });
      Future<LiveSubCategory?> prepare() => state.prepare(
        key: _key(detail),
        detail: detail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      expect(await prepare(), isNull);
      expect(state.status, LiveRoomCategoryResolutionStatus.failed);
      expect(await prepare(), same(category));
      expect(attempts, 2);
    });

    test('a tag change invalidates cached unmatched results', () async {
      final resolver = _FakeResolver((_) async => null);
      final state = LiveRoomCategoryRecommendationState();
      final firstDetail = _detail(categoryId: 'first');
      await state.prepare(
        key: _key(firstDetail),
        detail: firstDetail,
        resolver: resolver,
        isCurrent: (_) => true,
      );
      final secondDetail = _detail(categoryId: 'second');
      await state.prepare(
        key: _key(secondDetail),
        detail: secondDetail,
        resolver: resolver,
        isCurrent: (_) => true,
      );

      expect(resolver.calls, 2);
      expect(state.status, LiveRoomCategoryResolutionStatus.unmatched);
    });

    test('request key trims room ids without folding case and uses detail id',
        () {
      final detail = _detail(roomId: 'CanonicalRoom');
      final key = LiveRoomCategoryRequestKey.forRoom(
        loadGeneration: 4,
        platformId: 'douyin',
        roomId: ' requested-room ',
        detail: detail,
      );
      expect(key.roomId, 'CanonicalRoom');
      expect(
        LiveRoomCategoryRequestKey.normalizeRoomId('  CaseSensitive  '),
        'CaseSensitive',
      );
    });
  });

  group('LiveRoomCategoryRecommendationPager', () {
    test('uses hasMore after an empty unique page and deduplicates room ids',
        () async {
      final pager = LiveRoomCategoryRecommendationPager<String>();
      final requestedPages = <int>[];

      await pager.refresh(
        currentRoomId: 'current',
        fetchPage: (page) async {
          requestedPages.add(page);
          return const LiveRoomCategoryRecommendationPage(
            items: <String>['current', 'room-a', ' room-a '],
            hasMore: true,
          );
        },
        roomIdOf: (roomId) => roomId,
      );
      expect(pager.items, <String>['room-a']);
      expect(pager.hasMore, isTrue);
      expect(pager.nextPage, 2);

      await pager.loadMore(
        currentRoomId: 'current',
        fetchPage: (page) async {
          requestedPages.add(page);
          return const LiveRoomCategoryRecommendationPage(
            items: <String>['room-a', 'room-b'],
            hasMore: false,
          );
        },
        roomIdOf: (roomId) => roomId,
      );

      expect(requestedPages, <int>[1, 2]);
      expect(pager.items, <String>['room-a', 'room-b']);
      expect(pager.hasMore, isFalse);
      expect(pager.nextPage, 3);
    });

    test('failed page keeps cursor so the same page can be retried', () async {
      final pager = LiveRoomCategoryRecommendationPager<String>();
      await pager.refresh(
        currentRoomId: 'current',
        fetchPage: (_) async => const LiveRoomCategoryRecommendationPage(
          items: <String>['room-a'],
          hasMore: true,
        ),
        roomIdOf: (roomId) => roomId,
      );
      var attempts = 0;

      await expectLater(
        pager.loadMore(
          currentRoomId: 'current',
          fetchPage: (page) async {
            attempts++;
            expect(page, 2);
            throw StateError('temporary failure');
          },
          roomIdOf: (roomId) => roomId,
        ),
        throwsStateError,
      );
      expect(pager.nextPage, 2);
      expect(pager.items, <String>['room-a']);

      await pager.loadMore(
        currentRoomId: 'current',
        fetchPage: (page) async {
          attempts++;
          expect(page, 2);
          return const LiveRoomCategoryRecommendationPage(
            items: <String>['room-b'],
            hasMore: false,
          );
        },
        roomIdOf: (roomId) => roomId,
      );

      expect(attempts, 2);
      expect(pager.nextPage, 3);
      expect(pager.items, <String>['room-a', 'room-b']);
    });

    test('a superseded request failure does not replace the newer result',
        () async {
      final pager = LiveRoomCategoryRecommendationPager<String>();
      final oldRequest = Completer<LiveRoomCategoryRecommendationPage<String>>();
      final older = pager.refresh(
        currentRoomId: 'current',
        fetchPage: (_) => oldRequest.future,
        roomIdOf: (roomId) => roomId,
      );
      await pager.refresh(
        currentRoomId: 'current',
        fetchPage: (_) async => const LiveRoomCategoryRecommendationPage(
          items: ['new'],
          hasMore: false,
        ),
        roomIdOf: (roomId) => roomId,
      );
      oldRequest.completeError(StateError('stale failure'));
      await older;
      expect(pager.items, ['new']);
      expect(pager.lastError, isNull);
      expect(pager.isLoading, isFalse);
    });

    test('newer refresh wins and stale refresh does not hold loading state',
        () async {
      final pager = LiveRoomCategoryRecommendationPager<String>();
      final oldRequest =
          Completer<LiveRoomCategoryRecommendationPage<String>>();
      final newRequest =
          Completer<LiveRoomCategoryRecommendationPage<String>>();
      final older = pager.refresh(
        currentRoomId: 'current',
        fetchPage: (_) => oldRequest.future,
        roomIdOf: (roomId) => roomId,
      );
      final newer = pager.refresh(
        currentRoomId: 'current',
        fetchPage: (_) => newRequest.future,
        roomIdOf: (roomId) => roomId,
      );

      newRequest.complete(const LiveRoomCategoryRecommendationPage(
        items: <String>['new'],
        hasMore: false,
      ));
      await newer;
      expect(pager.items, <String>['new']);
      expect(pager.isLoading, isFalse);

      oldRequest.complete(const LiveRoomCategoryRecommendationPage(
        items: <String>['old'],
        hasMore: true,
      ));
      await older;
      expect(pager.items, <String>['new']);
      expect(pager.hasMore, isFalse);
      expect(pager.isLoading, isFalse);
    });
  });
}

class _FakeResolver implements LiveRoomCategoryResolver {
  _FakeResolver(this.resolve);

  final Future<LiveSubCategory?> Function(LiveRoomDetail detail) resolve;
  int calls = 0;

  @override
  Future<LiveSubCategory?> resolveRoomCategory(LiveRoomDetail detail) {
    calls++;
    return resolve(detail);
  }
}

LiveRoomCategoryRequestKey _key(LiveRoomDetail detail) =>
    LiveRoomCategoryRequestKey.forRoom(
      loadGeneration: 1,
      platformId: 'test',
      roomId: detail.roomId,
      detail: detail,
    );

LiveRoomDetail _detail({
  String roomId = 'room-1',
  String? categoryId = 'game-id',
  String? categoryName = 'Game',
  String? categoryParentId = 'parent-id',
  String? categoryParentName = 'Parent',
}) =>
    LiveRoomDetail(
      roomId: roomId,
      title: 'Room title',
      cover: '',
      userName: 'User',
      userAvatar: '',
      online: 1,
      status: true,
      url: '',
      categoryId: categoryId,
      categoryName: categoryName,
      categoryParentId: categoryParentId,
      categoryParentName: categoryParentName,
    );

LiveSubCategory _category(String id) => LiveSubCategory(
      id: id,
      name: id,
      parentId: 'parent',
    );
