import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/xiaohongshu_host_id.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

class DBService extends GetxService {
  static DBService get instance => Get.find<DBService>();
  late Box<History> historyBox;
  late Box<FollowUser> followBox;
  late Box<FollowUserTag> tagBox;
  final Uuid uuid = const Uuid();
  Future<void> _xiaohongshuHistoryQueue = Future<void>.value();

  Future init() async {
    historyBox = await Hive.openBox("History");
    followBox = await Hive.openBox("FollowUser");
    tagBox = await Hive.openBox("FollowUserTag");
  }

  // follow_user_tag 相关逻辑
  bool getFollowTagExist(String id) {
    return tagBox.containsKey(id);
  }

  // 删除标签
  Future deleteFollowTag(String id) async {
    await tagBox.delete(id);
  }

  FollowUserTag? getFollowTag(String tag) {
    return tagBox.values.firstWhereOrNull((item) => item.tag == tag);
  }

  // 判断标签名称是否重复
  bool getFollowTagExistByTag(String tag) {
    return tagBox.values.any((item) => item.tag == tag);
  }

  // 获取标签列表
  List<FollowUserTag> getFollowTagList() {
    return tagBox.values.toList();
  }

  // 修改标签
  Future updateFollowTag(FollowUserTag followTag) async {
    await tagBox.put(followTag.id, followTag);
  }

  // 添加标签
  Future<FollowUserTag> addFollowTag(String tag) async {
    // 限制标签唯一且长度不超过8个字符
    if (getFollowTagExistByTag(tag) && tag.length > 8) {
      return getFollowTag(tag)!;
    }
    final String uniqueId = uuid.v4();
    final followUserTag = FollowUserTag(id: uniqueId, tag: tag, userId: []);
    await tagBox.put(uniqueId, followUserTag);
    return followUserTag;
  }

  // 调整标签顺序
  Future updateFollowTagOrder(List<FollowUserTag> userTagList) async {
    final Map<int, FollowUserTag> updatedMap = {
      for (int i = 0; i < userTagList.length; i++) i: userTagList[i]
    };
    await tagBox.clear();
    await tagBox.putAll(updatedMap);
  }

  bool getFollowExist(String id) {
    return followBox.containsKey(id);
  }

  List<FollowUser> getFollowList() {
    return followBox.values.toList();
  }

  Future addFollow(FollowUser follow) async {
    await followBox.put(follow.id, follow);
  }

  Future addFollows(Iterable<FollowUser> follows) async {
    await followBox.putAll({
      for (final follow in follows) follow.id: follow,
    });
  }

  Future deleteFollow(String id) async {
    await followBox.delete(id);
  }

  History? getHistory(String id) {
    if (historyBox.containsKey(id)) {
      return historyBox.get(id);
    }
    return null;
  }

  Future<void> addOrUpdateHistory(
    History history, {
    bool xiaohongshuRoomVerified = true,
  }) {
    if (history.siteId != Constant.kXiaohongshu) {
      return _addOrUpdateHistoryNow(history);
    }
    final result = _xiaohongshuHistoryQueue.then((_) => _addOrUpdateHistoryNow(
          history,
          xiaohongshuRoomVerified: xiaohongshuRoomVerified,
        ));
    _xiaohongshuHistoryQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _addOrUpdateHistoryNow(
    History history, {
    bool xiaohongshuRoomVerified = true,
  }) async {
    final existingRoom = historyBox.get(history.id);
    final hostId = normalizeXiaohongshuHostId(history.xiaohongshuHostId) ??
        normalizeXiaohongshuHostId(existingRoom?.xiaohongshuHostId);
    if (history.siteId == Constant.kXiaohongshu &&
        hostId != null &&
        hostId.isNotEmpty) {
      history.xiaohongshuHostId = hostId;
      final sameHost = historyBox.values
          .where((item) =>
              item.siteId == Constant.kXiaohongshu &&
              normalizeXiaohongshuHostId(item.xiaohongshuHostId) == hostId)
          .toList(growable: false);
      if (!xiaohongshuRoomVerified && sameHost.isNotEmpty) {
        final current = sameHost
            .reduce((a, b) => a.updateTime.isAfter(b.updateTime) ? a : b);
        final updatedCurrent = History(
          id: current.id,
          roomId: current.roomId,
          siteId: current.siteId,
          userName: current.userName,
          face: current.face,
          updateTime: history.updateTime.isAfter(current.updateTime)
              ? history.updateTime
              : current.updateTime,
          xiaohongshuHostId: hostId,
        );
        await historyBox.put(updatedCurrent.id, updatedCurrent);
        final obsoleteIds = sameHost
            .map((item) => item.id)
            .where((id) => id != current.id)
            .toSet();
        if (obsoleteIds.isNotEmpty) {
          await historyBox.deleteAll(obsoleteIds);
        }
        return;
      }
      var latestVisit = history.updateTime;
      for (final item in sameHost) {
        if (item.updateTime.isAfter(latestVisit)) {
          latestVisit = item.updateTime;
        }
      }
      final verifiedCurrent = History(
        id: history.id,
        roomId: history.roomId,
        siteId: history.siteId,
        userName: history.userName,
        face: history.face,
        updateTime: latestVisit,
        xiaohongshuHostId: hostId,
      );
      await historyBox.put(verifiedCurrent.id, verifiedCurrent);
      final obsoleteIds = sameHost
          .map((item) => item.id)
          .where((id) => id != verifiedCurrent.id)
          .toSet();
      if (obsoleteIds.isNotEmpty) {
        await historyBox.deleteAll(obsoleteIds);
      }
      return;
    }
    await historyBox.put(history.id, history);
  }

  String? getXiaohongshuHostIdForRoom(String roomId) {
    final follow = followBox.get('${Constant.kXiaohongshu}_$roomId');
    final followHostId = normalizeXiaohongshuHostId(follow?.xiaohongshuHostId);
    if (followHostId != null) return followHostId;
    final history = historyBox.get('${Constant.kXiaohongshu}_$roomId');
    return normalizeXiaohongshuHostId(history?.xiaohongshuHostId);
  }

  FollowUser? findXiaohongshuFollow({
    required String roomId,
    String? hostId,
  }) {
    final normalizedHostId = normalizeXiaohongshuHostId(hostId);
    FollowUser? roomMatch;
    FollowUser? hostMatch;
    FollowUser? exactMatch;
    for (final follow in followBox.values) {
      if (follow.siteId != Constant.kXiaohongshu) continue;
      final storedHostId = normalizeXiaohongshuHostId(follow.xiaohongshuHostId);
      if (normalizedHostId != null && storedHostId == normalizedHostId) {
        hostMatch ??= follow;
        if (follow.roomId == roomId) exactMatch = follow;
      }
      if (follow.roomId == roomId &&
          (normalizedHostId == null ||
              storedHostId == null ||
              storedHostId == normalizedHostId)) {
        roomMatch ??= follow;
      }
    }
    return exactMatch ?? hostMatch ?? roomMatch;
  }

  List<History> getHistores() {
    var his = historyBox.values.toList();
    his.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    return his;
  }
}
