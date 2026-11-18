import 'dart:math';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/models/auto_switch_item.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';

typedef AutoSwitchStatusResolver = Future<LiveStatusState> Function(
  AutoSwitchItem item,
);

class AutoSwitchListService extends GetxService {
  static AutoSwitchListService get instance =>
      Get.find<AutoSwitchListService>();

  static const boxName = 'TVAutoSwitchList';
  static const statusCacheTtl = Duration(seconds: 60);

  late Box<AutoSwitchItem> box;
  final items = <AutoSwitchItem>[].obs;
  final Random _random = Random();
  Future<void>? _statusRefreshFuture;
  int _mutationGeneration = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    box = await Hive.openBox<AutoSwitchItem>(boxName);
    _initialized = true;
    _reload();
  }

  void _reload() {
    final values = box.values.toList()
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    items.assignAll(values);
  }

  Future<void> addFollow(FollowUser follow) async {
    await addFollows([follow]);
  }

  Future<void> addFollows(Iterable<FollowUser> follows) async {
    final existing = items.map((item) => item.id).toSet();
    final pending = <String, AutoSwitchItem>{};
    var sortOrder = items.length;
    for (final follow in follows) {
      if (!existing.add(follow.id)) continue;
      pending[follow.id] = AutoSwitchItem(
        id: follow.id,
        siteId: follow.siteId,
        roomId: follow.roomId,
        userName: follow.userName,
        face: follow.face,
        roomCover: follow.roomCover,
        sortOrder: sortOrder++,
      );
    }
    if (pending.isEmpty) return;
    await box.putAll(pending);
    _mutationGeneration++;
    _reload();
  }

  Future<void> addItems(Iterable<AutoSwitchItem> values) async {
    final existing = items.map((item) => item.id).toSet();
    var sortOrder = items.length;
    final pending = <String, AutoSwitchItem>{};
    for (final item in values) {
      if (!existing.add(item.id)) continue;
      item.sortOrder = sortOrder++;
      pending[item.id] = item;
    }
    if (pending.isEmpty) return;
    await box.putAll(pending);
    _mutationGeneration++;
    _reload();
  }

  Future<void> remove(String id) async {
    if (!items.any((item) => item.id == id)) return;
    await box.delete(id);
    _mutationGeneration++;
    _reload();
    await _normalizeOrder();
  }

  Future<void> move(int oldIndex, int newIndex) async {
    final current = items.toList();
    if (oldIndex < 0 || oldIndex >= current.length) return;
    newIndex = newIndex.clamp(0, current.length).toInt();
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, current.length - 1).toInt();
    if (newIndex == oldIndex) return;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    for (var i = 0; i < current.length; i++) {
      current[i].sortOrder = i;
    }
    await box.putAll({for (final item in current) item.id: item});
    _mutationGeneration++;
    _reload();
  }

  /// Refreshes stale entries at most once at a time.
  ///
  /// A mutation made while requests are in flight invalidates the whole
  /// refresh, so an old response cannot overwrite a newly reordered or
  /// removed entry.
  Future<void> refreshStatuses({
    DateTime? now,
    AutoSwitchStatusResolver? resolver,
  }) {
    final running = _statusRefreshFuture;
    if (running != null) return running;
    final refresh = _refreshStatuses(
      checkedAt: now ?? DateTime.now(),
      resolver: resolver,
      generation: _mutationGeneration,
    );
    late Future<void> tracked;
    tracked = refresh.whenComplete(() {
      if (identical(_statusRefreshFuture, tracked)) {
        _statusRefreshFuture = null;
      }
    });
    _statusRefreshFuture = tracked;
    return tracked;
  }

  AutoSwitchItem? nextLive(String currentId, {bool random = false}) {
    final live = items.where((item) => item.liveStatus == 2).toList();
    if (live.isEmpty) return null;
    final candidates = live.where((item) => item.id != currentId).toList();
    if (candidates.isEmpty) return null;
    if (random) return candidates[_random.nextInt(candidates.length)];

    final currentIndex = items.indexWhere((item) => item.id == currentId);
    final start = currentIndex < 0 ? -1 : currentIndex;
    for (var offset = 1; offset <= items.length; offset++) {
      final item = items[(start + offset) % items.length];
      if (item.liveStatus == 2 && item.id != currentId) return item;
    }
    return null;
  }

  Future<void> _normalizeOrder() async {
    final current = items.toList();
    for (var i = 0; i < current.length; i++) {
      current[i].sortOrder = i;
    }
    await box.putAll({for (final item in current) item.id: item});
    _reload();
  }

  Future<void> _refreshStatuses({
    required DateTime checkedAt,
    required AutoSwitchStatusResolver? resolver,
    required int generation,
  }) async {
    final targets = items
        .where((item) => !isStatusFresh(item.statusCheckedAt, checkedAt))
        .toList(growable: false);
    if (targets.isEmpty) return;

    final results = await Future.wait(
      targets.map((item) async {
        var status = 0;
        try {
          final state = await (resolver ?? _resolveStatus)(item);
          status = state == LiveStatusState.live
              ? 2
              : state == LiveStatusState.offline
                  ? 1
                  : 0;
        } catch (_) {
          status = 0;
        }
        return (item: item, status: status);
      }),
    );
    if (generation != _mutationGeneration) return;
    for (final result in results) {
      result.item.liveStatus = result.status;
      result.item.statusCheckedAt = checkedAt;
    }
    if (_initialized) {
      await box
          .putAll({for (final result in results) result.item.id: result.item});
    }
    _reloadIfInitialized();
  }

  Future<LiveStatusState> _resolveStatus(AutoSwitchItem item) async {
    final site = Sites.allSites[item.siteId];
    if (site == null) return LiveStatusState.unknown;
    return site.liveSite.getLiveStatusState(roomId: item.roomId);
  }

  void _reloadIfInitialized() {
    if (_initialized) _reload();
  }

  static bool isStatusFresh(DateTime? checkedAt, DateTime now) {
    return checkedAt != null && now.difference(checkedAt) < statusCacheTtl;
  }
}
