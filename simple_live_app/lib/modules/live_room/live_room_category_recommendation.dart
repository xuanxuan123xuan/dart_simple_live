import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';

/// Identity of one attempt to resolve a room's provider category.
///
/// Room ids and category tags are trimmed, while provider ids and names remain
/// case sensitive. A detail-provided room id is the canonical request identity.
class LiveRoomCategoryRequestKey {
  LiveRoomCategoryRequestKey({
    required this.loadGeneration,
    required this.platformId,
    required String roomId,
    required String? categoryId,
    required String? categoryParentId,
    required String? categoryName,
    required String? categoryParentName,
  })  : roomId = normalizeRoomId(roomId),
        categoryId = _normalizeTag(categoryId),
        categoryParentId = _normalizeTag(categoryParentId),
        categoryName = _normalizeTag(categoryName),
        categoryParentName = _normalizeTag(categoryParentName);

  factory LiveRoomCategoryRequestKey.forRoom({
    required int loadGeneration,
    required String platformId,
    required String roomId,
    required LiveRoomDetail? detail,
  }) {
    return LiveRoomCategoryRequestKey(
      loadGeneration: loadGeneration,
      platformId: platformId,
      roomId:
          detail?.roomId.trim().isNotEmpty == true ? detail!.roomId : roomId,
      categoryId: detail?.categoryId,
      categoryParentId: detail?.categoryParentId,
      categoryName: detail?.categoryName,
      categoryParentName: detail?.categoryParentName,
    );
  }

  final int loadGeneration;
  final String platformId;
  final String roomId;
  final String categoryId;
  final String categoryParentId;
  final String categoryName;
  final String categoryParentName;

  bool get hasTags =>
      categoryId.isNotEmpty ||
      categoryParentId.isNotEmpty ||
      categoryName.isNotEmpty ||
      categoryParentName.isNotEmpty;

  String get identity => jsonEncode(<Object>[
        loadGeneration,
        platformId,
        roomId,
        categoryId,
        categoryParentId,
        categoryName,
        categoryParentName,
      ]);

  static String normalizeRoomId(String value) => value.trim();

  static String _normalizeTag(String? value) => value?.trim() ?? '';

  @override
  bool operator ==(Object other) =>
      other is LiveRoomCategoryRequestKey && identity == other.identity;

  @override
  int get hashCode => identity.hashCode;
}

enum LiveRoomCategoryResolutionStatus {
  waitingForDetail,
  idle,
  resolving,
  available,
  missingTags,
  unmatched,
  failed,
}

/// Owns category lookup state independently of the large live-room
/// controller. Matching in-flight requests are shared; stale completions are
/// ignored when a room, load generation, platform, or tag changes.
class LiveRoomCategoryRecommendationState {
  LiveRoomCategoryRecommendationState({this.onChanged});

  final void Function()? onChanged;

  LiveRoomCategoryRequestKey? _key;
  LiveRoomCategoryRequestKey? _inFlightKey;
  Future<LiveSubCategory?>? _inFlight;
  int _requestGeneration = 0;

  LiveRoomCategoryResolutionStatus status =
      LiveRoomCategoryResolutionStatus.waitingForDetail;
  LiveSubCategory? category;

  /// Read current context without changing state during a widget build.
  LiveRoomCategoryResolutionStatus statusFor(
    LiveRoomCategoryRequestKey key, {
    required bool hasDetail,
  }) {
    if (!hasDetail) return LiveRoomCategoryResolutionStatus.waitingForDetail;
    if (_key == key) return status;
    return key.hasTags
        ? LiveRoomCategoryResolutionStatus.idle
        : LiveRoomCategoryResolutionStatus.missingTags;
  }

  LiveSubCategory? categoryFor(LiveRoomCategoryRequestKey key) =>
      _key == key && status == LiveRoomCategoryResolutionStatus.available
          ? category
          : null;

  void syncContext(
    LiveRoomCategoryRequestKey key, {
    required bool hasDetail,
  }) {
    if (_key == key &&
        (hasDetail
            ? status != LiveRoomCategoryResolutionStatus.waitingForDetail
            : status == LiveRoomCategoryResolutionStatus.waitingForDetail)) {
      return;
    }
    _key = key;
    _requestGeneration += 1;
    _inFlight = null;
    _inFlightKey = null;
    category = null;
    if (!hasDetail) {
      status = LiveRoomCategoryResolutionStatus.waitingForDetail;
    } else if (!key.hasTags) {
      status = LiveRoomCategoryResolutionStatus.missingTags;
    } else {
      status = LiveRoomCategoryResolutionStatus.idle;
    }
    onChanged?.call();
  }

  Future<LiveSubCategory?> prepare({
    required LiveRoomCategoryRequestKey key,
    required LiveRoomDetail? detail,
    required LiveRoomCategoryResolver resolver,
    required bool Function(LiveRoomCategoryRequestKey key) isCurrent,
  }) {
    syncContext(key, hasDetail: detail != null);
    if (detail == null || !key.hasTags) {
      return Future<LiveSubCategory?>.value(null);
    }
    if (_inFlight != null && _inFlightKey == key) {
      return _inFlight!;
    }
    if (_key != key) {
      return Future<LiveSubCategory?>.value(null);
    }
    if (status == LiveRoomCategoryResolutionStatus.available ||
        status == LiveRoomCategoryResolutionStatus.unmatched) {
      return Future<LiveSubCategory?>.value(category);
    }

    final requestGeneration = ++_requestGeneration;
    status = LiveRoomCategoryResolutionStatus.resolving;
    category = null;
    onChanged?.call();
    _inFlightKey = key;
    final request = _resolve(
      key: key,
      detail: detail,
      resolver: resolver,
      requestGeneration: requestGeneration,
      isCurrent: isCurrent,
    );
    _inFlight = request;
    return request;
  }

  Future<LiveSubCategory?> _resolve({
    required LiveRoomCategoryRequestKey key,
    required LiveRoomDetail detail,
    required LiveRoomCategoryResolver resolver,
    required int requestGeneration,
    required bool Function(LiveRoomCategoryRequestKey key) isCurrent,
  }) async {
    try {
      final resolved = await Future.sync(() => resolver.resolveRoomCategory(detail));
      if (!_isCurrentRequest(key, requestGeneration, isCurrent)) {
        return null;
      }
      category = resolved;
      status = resolved == null
          ? LiveRoomCategoryResolutionStatus.unmatched
          : LiveRoomCategoryResolutionStatus.available;
      onChanged?.call();
      return resolved;
    } catch (_) {
      if (_isCurrentRequest(key, requestGeneration, isCurrent)) {
        category = null;
        status = LiveRoomCategoryResolutionStatus.failed;
        onChanged?.call();
      }
      return null;
    } finally {
      if (_inFlightKey == key && _requestGeneration == requestGeneration) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }

  bool _isCurrentRequest(
    LiveRoomCategoryRequestKey key,
    int requestGeneration,
    bool Function(LiveRoomCategoryRequestKey key) isCurrent,
  ) =>
      _key == key && _requestGeneration == requestGeneration && isCurrent(key);

  /// Invalidates outstanding work when this controller is disposed.
  void invalidate() {
    _requestGeneration += 1;
    _key = null;
    _inFlightKey = null;
    _inFlight = null;
    category = null;
    status = LiveRoomCategoryResolutionStatus.waitingForDetail;
    onChanged?.call();
  }
}

class LiveRoomCategoryRecommendationPage<T> {
  const LiveRoomCategoryRecommendationPage({
    required this.items,
    required this.hasMore,
  });

  final List<T> items;
  final bool hasMore;
}

/// Stable, testable pagination for the quick-access recommendation list.
///
/// A refresh supersedes all earlier requests. Failed requests keep the page
/// cursor and list intact, and `hasMore` is taken from the endpoint even when
/// a page contributes no unique rooms.
class LiveRoomCategoryRecommendationPager<T> {
  LiveRoomCategoryRecommendationPager({this.onChanged});

  final void Function()? onChanged;

  final List<T> items = <T>[];
  int nextPage = 1;
  bool hasMore = true;
  bool _loadingMore = false;
  int _generation = 0;
  int? _activeRefreshGeneration;
  Object? lastError;

  bool get isRefreshing => _activeRefreshGeneration == _generation;
  bool get isLoading => isRefreshing || _loadingMore;

  Future<void> refresh({
    required String currentRoomId,
    required Future<LiveRoomCategoryRecommendationPage<T>> Function(int page)
        fetchPage,
    required String Function(T item) roomIdOf,
  }) {
    final generation = ++_generation;
    _loadingMore = false;
    _activeRefreshGeneration = generation;
    lastError = null;
    onChanged?.call();
    return _load(
      generation: generation,
      page: 1,
      refresh: true,
      currentRoomId: currentRoomId,
      fetchPage: fetchPage,
      roomIdOf: roomIdOf,
    );
  }

  Future<void> loadMore({
    required String currentRoomId,
    required Future<LiveRoomCategoryRecommendationPage<T>> Function(int page)
        fetchPage,
    required String Function(T item) roomIdOf,
  }) {
    if (!hasMore || isLoading) return Future<void>.value();
    _loadingMore = true;
    lastError = null;
    onChanged?.call();
    return _load(
      generation: _generation,
      page: nextPage,
      refresh: false,
      currentRoomId: currentRoomId,
      fetchPage: fetchPage,
      roomIdOf: roomIdOf,
    );
  }

  Future<void> _load({
    required int generation,
    required int page,
    required bool refresh,
    required String currentRoomId,
    required Future<LiveRoomCategoryRecommendationPage<T>> Function(int page)
        fetchPage,
    required String Function(T item) roomIdOf,
  }) async {
    try {
      final result = await fetchPage(page);
      if (generation != _generation) return;
      final existing = refresh ? <T>[] : List<T>.of(items);
      final excludedId =
          LiveRoomCategoryRequestKey.normalizeRoomId(currentRoomId);
      final seen = <String>{excludedId};
      for (final item in existing) {
        seen.add(LiveRoomCategoryRequestKey.normalizeRoomId(roomIdOf(item)));
      }
      final merged = <T>[...existing];
      for (final item in result.items) {
        final id = LiveRoomCategoryRequestKey.normalizeRoomId(roomIdOf(item));
        if (id.isEmpty || !seen.add(id)) continue;
        merged.add(item);
      }
      items
        ..clear()
        ..addAll(merged);
      nextPage = page + 1;
      hasMore = result.hasMore;
      lastError = null;
    } catch (error) {
      if (generation != _generation) return;
      lastError = error;
      rethrow;
    } finally {
      if (refresh && generation == _generation) {
        _activeRefreshGeneration = null;
      } else if (generation == _generation) {
        _loadingMore = false;
      }
      onChanged?.call();
    }
  }
}
