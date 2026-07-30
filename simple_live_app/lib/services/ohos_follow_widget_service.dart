import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';

/// 向鸿蒙服务卡片同步关注列表快照。
///
/// 卡片运行在独立的 ArkTS 进程里，没有 Flutter 引擎，因此无法调用
/// `simple_live_core` 解析开播状态。这里在每轮关注刷新结束后把结果写成快照，
/// 卡片只负责渲染，不联网。
class OhosFollowWidgetService {
  OhosFollowWidgetService._();

  static const MethodChannel _channel =
      MethodChannel('simple_live/ohos_widget');

  /// 卡片最多展示的条目数。取前若干条即可，避免把整个关注列表塞进
  /// preferences（卡片数据有大小限制，且渲染不下）。
  static const int maxItems = 20;

  /// 需要签名/登录态才能查开播状态的站点，后台任务会跳过它们。
  static const Set<String> signRequiredSites = {'douyin', 'kuaishou'};

  /// 把 [followList] 序列化后写入鸿蒙侧。非鸿蒙平台直接返回。
  ///
  /// 失败只记日志，不抛出：卡片同步属于附带能力，不应影响关注刷新。
  static Future<void> syncSnapshot(List<FollowUser> followList) async {
    if (!Utils.isOhos) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'payload': buildPayload(followList),
      });
    } catch (e) {
      Log.d('同步鸿蒙关注卡片失败: $e');
    }
  }

  /// 启用后台特别关注检查（鸿蒙 WorkScheduler）。
  ///
  /// 系统对重复任务的最小间隔约 2 小时，且可能延迟执行，因此这是前台
  /// 轮询的兜底，不是替代。
  static Future<bool> startBackgroundCheck() async {
    if (!Utils.isOhos) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('startFollowCheck') ?? false;
    } catch (e) {
      Log.d('启动鸿蒙后台关注检查失败: $e');
      return false;
    }
  }

  /// 停止后台特别关注检查。
  static Future<void> stopBackgroundCheck() async {
    if (!Utils.isOhos) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('stopFollowCheck');
    } catch (e) {
      Log.d('停止鸿蒙后台关注检查失败: $e');
    }
  }

  /// 构造快照 JSON。抽成公开方法便于单测。
  static String buildPayload(List<FollowUser> followList) {
    final sorted = sortForCard(followList);
    return jsonEncode({
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'items': sorted.map(_itemToJson).toList(),
    });
  }

  /// 直播中优先，其次特别关注，最后按原顺序；截断到 [maxItems]。
  static List<FollowUser> sortForCard(List<FollowUser> followList) {
    final indexed = followList.indexed.toList();
    indexed.sort((a, b) {
      final living =
          _livingRank(a.$2).compareTo(_livingRank(b.$2));
      if (living != 0) return living;
      final special = _specialRank(a.$2).compareTo(_specialRank(b.$2));
      if (special != 0) return special;
      return a.$1.compareTo(b.$1);
    });
    final result = indexed.map((e) => e.$2).toList();
    if (result.length <= maxItems) {
      return result;
    }
    return result.sublist(0, maxItems);
  }

  static int _livingRank(FollowUser item) => item.liveStatus.value == 2 ? 0 : 1;

  static int _specialRank(FollowUser item) => item.isSpecialFollow ? 0 : 1;

  static Map<String, Object?> _itemToJson(FollowUser item) {
    return {
      'siteId': item.siteId,
      'roomId': item.roomId,
      'userName': item.userName,
      'face': item.face,
      'roomTitle': item.roomTitle,
      'living': item.liveStatus.value == 2,
      'special': item.isSpecialFollow,
      'needsSign': signRequiredSites.contains(item.siteId),
    };
  }
}
