import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/current_room_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

const _hostId = '5eafa4cc0000000001005613';
const _otherHostId = '5eafa4cc0000000001005614';

void main() {
  late Directory directory;
  late DBService db;
  late FollowService follows;
  late String followBoxName;
  late String historyBoxName;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('xhs_identity_');
    Hive.init(directory.path);
    Hive.registerAdapter(FollowUserAdapter());
    Hive.registerAdapter(FollowUserTagAdapter());
    Hive.registerAdapter(HistoryAdapter());
  });

  setUp(() async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    followBoxName = 'xhs_follow_$suffix';
    historyBoxName = 'xhs_history_$suffix';
    db = DBService()
      ..followBox = await Hive.openBox<FollowUser>(followBoxName)
      ..tagBox = await Hive.openBox<FollowUserTag>('xhs_tags_$suffix')
      ..historyBox = await Hive.openBox<History>(historyBoxName);
    Get.put<DBService>(db);
    follows = FollowService();
  });

  tearDown(() async {
    await db.followBox.deleteFromDisk();
    await db.tagBox.deleteFromDisk();
    await db.historyBox.deleteFromDisk();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('old JSON remains readable and host IDs survive JSON and Hive',
      () async {
    final oldFollow = FollowUser.fromJson({
      'siteId': Constant.kXiaohongshu,
      'roomId': 'A',
      'userName': '主播',
    });
    final oldHistory = History.fromJson({
      'siteId': Constant.kXiaohongshu,
      'roomId': 'A',
      'userName': '主播',
    });
    expect(oldFollow.xiaohongshuHostId, isNull);
    expect(oldHistory.xiaohongshuHostId, isNull);

    final follow = _follow('B', hostId: _hostId);
    final history = _history('B', DateTime(2026, 10, 16), hostId: _hostId);
    expect(FollowUser.fromJson(follow.toJson()).xiaohongshuHostId, _hostId);
    expect(History.fromJson(history.toJson()).xiaohongshuHostId, _hostId);
    await db.followBox.put(follow.id, follow);
    await db.historyBox.put(history.id, history);
    await db.followBox.close();
    await db.historyBox.close();
    db.followBox = await Hive.openBox<FollowUser>(followBoxName);
    db.historyBox = await Hive.openBox<History>(historyBoxName);
    expect(db.followBox.get(follow.id)?.xiaohongshuHostId, _hostId);
    expect(db.historyBox.get(history.id)?.xiaohongshuHostId, _hostId);
  });

  test(
      'first confirmed polling identity finds an anchor followed on another room',
      () async {
    final followedAnchor = _follow('C', hostId: _hostId);
    await db.followBox.put(followedAnchor.id, followedAnchor);
    final currentRoom = Get.put(CurrentRoomService());
    final settings = Get.put<AppSettingsController>(_IdentitySettings());
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kXiaohongshu]!,
      pRoomId: 'A',
    );
    expect(controller.followed.value, isFalse);

    controller.applyXiaohongshuRoomIdentity(_detail('B', hostId: _hostId));

    expect(controller.roomId, 'B');
    expect(currentRoom.roomId.value, 'B');
    expect((settings as _IdentitySettings).savedRoomId, 'B');
    expect(controller.followed.value, isTrue);
    // The button must be correct even before asynchronous follow-key migration.
    expect(db.followBox.keys, ['xiaohongshu_C']);
  });

  test(
      'polling identity clears stale followed state and rejects another anchor',
      () async {
    await db.followBox.put('xiaohongshu_B', _follow('B', hostId: _otherHostId));
    Get.put(CurrentRoomService());
    Get.put<AppSettingsController>(_IdentitySettings());
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kXiaohongshu]!,
      pRoomId: 'A',
    )..followed.value = true;

    controller.applyXiaohongshuRoomIdentity(_detail('B', hostId: _hostId));

    expect(controller.roomId, 'B');
    expect(controller.followed.value, isFalse);
    controller.applyXiaohongshuRoomIdentity(_detail('C', hostId: _otherHostId));
    expect(controller.roomId, 'B');
    expect(controller.followed.value, isFalse);
  });

  test('learning an anchor refreshes followed state without changing the room',
      () async {
    final followedAnchor = _follow('C', hostId: _hostId);
    await db.followBox.put(followedAnchor.id, followedAnchor);
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kXiaohongshu]!,
      pRoomId: 'B',
    );

    controller.applyXiaohongshuRoomIdentity(_detail('B', hostId: _hostId));

    expect(controller.roomId, 'B');
    expect(controller.followed.value, isTrue);
  });

  test(
      'polling persists a newly learned host without rewriting unchanged history',
      () async {
    await db.historyBox.put('xiaohongshu_A', _history('A', DateTime(2026)));
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kXiaohongshu]!,
      pRoomId: 'A',
    );
    final writes = <BoxEvent>[];
    final subscription = db.historyBox.watch().listen(writes.add);
    final persisted = db.historyBox
        .watch(key: 'xiaohongshu_A')
        .first
        .timeout(const Duration(seconds: 5));

    controller.applyXiaohongshuRoomIdentity(
      _detail('A', hostId: _hostId),
      persistHistory: true,
    );
    await persisted;
    expect(db.historyBox.get('xiaohongshu_A')?.xiaohongshuHostId, _hostId);

    controller.applyXiaohongshuRoomIdentity(
      _detail('A', hostId: _hostId),
      persistHistory: true,
    );
    await pumpEventQueue();
    expect(writes, hasLength(1));
    await subscription.cancel();
  });

  test('unknown polling keeps its recovery host without rolling history B back',
      () async {
    final current = _history('B', DateTime(2026), hostId: _hostId);
    await db.historyBox.put(current.id, current);
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kXiaohongshu]!,
      pRoomId: 'A',
    );
    final persisted = db.historyBox
        .watch(key: current.id)
        .first
        .timeout(const Duration(seconds: 5));

    controller.applyXiaohongshuRoomIdentity(
      _detail('A', hostId: _hostId, state: LiveStatusState.unknown),
      persistHistory: true,
    );
    await persisted;

    expect(controller.roomId, 'A');
    expect(db.historyBox.keys, [current.id]);
    expect(db.historyBox.get(current.id)?.roomId, 'B');
    expect(db.historyBox.get(current.id)?.xiaohongshuHostId, _hostId);
  });

  test('unknown polling persists its newly discovered recovery identity',
      () async {
    final controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kXiaohongshu]!,
      pRoomId: 'A',
    );
    controller.detail.value = _detail('A', state: LiveStatusState.unknown);
    final persisted = db.historyBox
        .watch(key: 'xiaohongshu_A')
        .first
        .timeout(const Duration(seconds: 5));

    controller.applyXiaohongshuRoomIdentity(
      _detail('A', hostId: _hostId, state: LiveStatusState.unknown),
      persistHistory: true,
    );
    await persisted;

    expect(db.historyBox.get('xiaohongshu_A')?.xiaohongshuHostId, _hostId);
    expect(db.historyBox.get('xiaohongshu_A')?.roomId, 'A');
    expect(
        controller.detail.value?.resolvedLiveStatus, LiveStatusState.unknown);
  });

  test('known host migrates old room and unions follow tags', () async {
    final old = _follow('A', hostId: _hostId, addTime: DateTime(2025));
    final duplicate = _follow(
      'B',
      hostId: _hostId,
      addTime: DateTime(2026),
      special: true,
    );
    await db.followBox.putAll({old.id: old, duplicate.id: duplicate});
    await db.tagBox.putAll({
      't1': FollowUserTag(id: 't1', tag: '常看', userId: [old.id]),
      't2': FollowUserTag(id: 't2', tag: '收藏', userId: [duplicate.id]),
    });
    final requestId = follows.beginXiaohongshuIdentityRequest(
      roomId: 'A',
      hostId: _hostId,
    );
    await follows.syncFollowStatusFromRoomDetail(
      _detail('B', hostId: _hostId, title: '现在的标题'),
      siteId: Constant.kXiaohongshu,
      requestedRoomId: 'A',
      xiaohongshuRequestId: requestId,
    );

    expect(db.followBox.keys, ['xiaohongshu_B']);
    final merged = db.followBox.values.single;
    expect(merged.addTime, DateTime(2025));
    expect(merged.isSpecialFollow, isTrue);
    expect(merged.roomTitle, '现在的标题');
    expect(merged.xiaohongshuHostId, _hostId);
    expect(db.tagBox.get('t1')?.userId, [merged.id]);
    expect(db.tagBox.get('t2')?.userId, [merged.id]);
  });

  test('old follow without host migrates only after verified room detail',
      () async {
    final old = _follow('A');
    await db.followBox.put(old.id, old);
    final requestId = follows.beginXiaohongshuIdentityRequest(roomId: 'A');
    await follows.syncFollowStatusFromRoomDetail(
      _detail('B', hostId: _hostId),
      siteId: Constant.kXiaohongshu,
      requestedRoomId: 'A',
      xiaohongshuRequestId: requestId,
    );
    expect(db.followBox.get('xiaohongshu_A'), isNull);
    expect(db.followBox.get('xiaohongshu_B')?.xiaohongshuHostId, _hostId);
  });

  test('unknown detail preserves old key and last known live state', () async {
    final old = _follow('A', hostId: _hostId)..liveStatus.value = 2;
    await db.followBox.put(old.id, old);
    final requestId = follows.beginXiaohongshuIdentityRequest(
      roomId: 'A',
      hostId: _hostId,
    );
    await follows.syncFollowStatusFromRoomDetail(
      _detail('B', hostId: _hostId, state: LiveStatusState.unknown),
      siteId: Constant.kXiaohongshu,
      requestedRoomId: 'A',
      xiaohongshuRequestId: requestId,
    );
    expect(db.followBox.get(old.id), isNotNull);
    expect(db.followBox.get('xiaohongshu_B'), isNull);
    expect(old.liveStatus.value, 2);
    expect(old.liveCheckState.value, FollowLiveCheckState.unknown);
  });

  test('older completion for same host cannot migrate current B back to A',
      () async {
    final old = _follow('A', hostId: _hostId);
    await db.followBox.put(old.id, old);
    final stale = follows.beginXiaohongshuIdentityRequest(
      roomId: 'A',
      hostId: _hostId,
    );
    final current = follows.beginXiaohongshuIdentityRequest(
      roomId: 'B',
      hostId: _hostId,
    );
    await follows.syncFollowStatusFromRoomDetail(
      _detail('B', hostId: _hostId),
      siteId: Constant.kXiaohongshu,
      requestedRoomId: 'A',
      xiaohongshuRequestId: stale,
    );
    await follows.syncFollowStatusFromRoomDetail(
      _detail('B', hostId: _hostId),
      siteId: Constant.kXiaohongshu,
      requestedRoomId: 'B',
      xiaohongshuRequestId: current,
    );
    expect(db.followBox.keys, ['xiaohongshu_B']);
    expect(db.followBox.values.single.xiaohongshuHostId, _hostId);
  });

  test('new request during Hive put leaves one key and migrated tags',
      () async {
    final old = _follow('A', hostId: _hostId);
    await db.followBox.put(old.id, old);
    await db.tagBox.put(
      't1',
      FollowUserTag(id: 't1', tag: '常看', userId: [old.id]),
    );
    final realBox = db.followBox;
    final delayedBox = _DelayedFollowBox(realBox);
    db.followBox = delayedBox;
    try {
      var oldLoadCurrent = true;
      final oldRequest = follows.beginXiaohongshuIdentityRequest(
        roomId: 'A',
        hostId: _hostId,
      );
      final oldSync = follows.syncFollowStatusFromRoomDetail(
        _detail('B', hostId: _hostId),
        siteId: Constant.kXiaohongshu,
        requestedRoomId: 'A',
        xiaohongshuRequestId: oldRequest,
        isStillCurrent: () => oldLoadCurrent,
      );
      await delayedBox.firstPutStarted.future;
      oldLoadCurrent = false;
      final newRequest = follows.beginXiaohongshuIdentityRequest(
        roomId: 'B',
        hostId: _hostId,
      );
      final newSync = follows.syncFollowStatusFromRoomDetail(
        _detail('B', hostId: _hostId, state: LiveStatusState.offline),
        siteId: Constant.kXiaohongshu,
        requestedRoomId: 'B',
        xiaohongshuRequestId: newRequest,
      );
      delayedBox.releaseFirstPut.complete();
      await Future.wait([oldSync, newSync]);

      expect(db.followBox.keys, ['xiaohongshu_B']);
      expect(db.tagBox.get('t1')?.userId, ['xiaohongshu_B']);
      expect(db.followBox.get('xiaohongshu_B')?.liveStatus.value, 1);
    } finally {
      if (!delayedBox.releaseFirstPut.isCompleted) {
        delayedBox.releaseFirstPut.complete();
      }
      db.followBox = realBox;
    }
  });

  test('host mismatch cannot match or replace another anchor', () async {
    final other = _follow('B', hostId: _otherHostId);
    await db.followBox.put(other.id, other);
    expect(db.findXiaohongshuFollow(roomId: 'B', hostId: _hostId), isNull);
    await follows.addFollow(_follow('A', hostId: _hostId));
    await follows.syncFollowStatusFromRoomDetail(
      _detail('B', hostId: _hostId),
      siteId: Constant.kXiaohongshu,
      requestedRoomId: 'A',
    );
    expect(db.followBox.get(other.id)?.xiaohongshuHostId, _otherHostId);
    expect(db.followBox.get('xiaohongshu_A')?.xiaohongshuHostId, _hostId);
  });

  test('unknown old link updates visit time on current room without rollback',
      () async {
    final oldVisit = DateTime(2026, 10, 15);
    final newVisit = DateTime(2026, 10, 16);
    final obsolete = _history('A', DateTime(2026, 10, 14), hostId: _hostId);
    final current = _history('B', oldVisit, hostId: _hostId);
    await db.historyBox.put(obsolete.id, obsolete);
    await db.historyBox.put(current.id, current);
    await db.addOrUpdateHistory(
      _history('A', newVisit, hostId: _hostId),
      xiaohongshuRoomVerified: false,
    );
    expect(db.historyBox.keys, [current.id]);
    expect(db.historyBox.values.single.updateTime, newVisit);
    expect(db.historyBox.values.single.roomId, 'B');
    expect(current.updateTime, oldVisit);
  });

  test('verified new room replaces old history and keeps latest visit',
      () async {
    await db.historyBox.put(
      'xiaohongshu_A',
      _history('A', DateTime(2026, 10, 15), hostId: _hostId),
    );
    await db.addOrUpdateHistory(
      _history('B', DateTime(2026, 10, 16), hostId: _hostId),
    );
    expect(db.historyBox.keys, ['xiaohongshu_B']);
    expect(db.historyBox.values.single.updateTime, DateTime(2026, 10, 16));
  });

  test('verified current room wins over a later visit timestamp on old key',
      () async {
    final laterVisit = DateTime(2026, 10, 17);
    await db.historyBox.put(
      'xiaohongshu_A',
      _history('A', laterVisit, hostId: _hostId),
    );
    await db.addOrUpdateHistory(
      _history('B', DateTime(2026, 10, 16), hostId: _hostId),
    );
    expect(db.historyBox.keys, ['xiaohongshu_B']);
    expect(db.historyBox.values.single.updateTime, laterVisit);
  });
}

FollowUser _follow(
  String roomId, {
  String? hostId,
  DateTime? addTime,
  bool special = false,
}) =>
    FollowUser(
      id: '${Constant.kXiaohongshu}_$roomId',
      roomId: roomId,
      siteId: Constant.kXiaohongshu,
      userName: '主播',
      face: 'avatar',
      addTime: addTime ?? DateTime(2026),
      isSpecialFollow: special,
      xiaohongshuHostId: hostId,
    );

History _history(String roomId, DateTime visit, {String? hostId}) => History(
      id: '${Constant.kXiaohongshu}_$roomId',
      roomId: roomId,
      siteId: Constant.kXiaohongshu,
      userName: '主播',
      face: 'avatar',
      updateTime: visit,
      xiaohongshuHostId: hostId,
    );

LiveRoomDetail _detail(
  String roomId, {
  String? hostId,
  String title = '标题',
  LiveStatusState state = LiveStatusState.live,
}) =>
    LiveRoomDetail(
      roomId: roomId,
      title: title,
      cover: 'cover',
      userName: '主播',
      userAvatar: 'avatar',
      online: 10,
      status: state == LiveStatusState.live,
      liveStatusState: state,
      url: 'https://www.xiaohongshu.com/livestream/$roomId',
      data: XiaohongshuRoomSnapshot(
        roomId: roomId,
        title: title,
        cover: 'cover',
        userName: '主播',
        userAvatar: 'avatar',
        online: 10,
        live: state == LiveStatusState.live,
        liveStatus: state == LiveStatusState.unknown ? 'unknown' : 'success',
        roomStatus: state == LiveStatusState.live ? 1 : 0,
        streams: const [],
        url: 'https://www.xiaohongshu.com/livestream/$roomId',
        hostId: hostId,
      ),
    );

class _IdentitySettings extends AppSettingsController {
  String? savedRoomId;

  @override
  // Storage is not needed when testing how a resolved identity updates the UI.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> saveLastLiveRoom({
    required String siteId,
    required String roomId,
    bool resumePending = false,
  }) async {
    savedRoomId = roomId;
  }
}

class _DelayedFollowBox extends Fake implements Box<FollowUser> {
  _DelayedFollowBox(this.inner);

  final Box<FollowUser> inner;
  final firstPutStarted = Completer<void>();
  final releaseFirstPut = Completer<void>();
  bool _delayed = false;

  @override
  Iterable<FollowUser> get values => inner.values;

  @override
  Iterable<dynamic> get keys => inner.keys;

  @override
  FollowUser? get(dynamic key, {FollowUser? defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);

  @override
  bool containsKey(dynamic key) => inner.containsKey(key);

  @override
  Future<void> put(dynamic key, FollowUser value) async {
    await inner.put(key, value);
    if (!_delayed && key == 'xiaohongshu_B') {
      _delayed = true;
      firstPutStarted.complete();
      await releaseFirstPut.future;
    }
  }

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) => inner.deleteAll(keys);

  @override
  Future<void> delete(dynamic key) => inner.delete(key);
}
