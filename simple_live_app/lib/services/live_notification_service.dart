import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';

class LiveNotificationTarget {
  const LiveNotificationTarget({
    required this.siteId,
    required this.roomId,
  });

  final String siteId;
  final String roomId;

  static LiveNotificationTarget? tryParse(Object? value) {
    if (value is! Map) return null;
    final siteId = value['siteId']?.toString().trim() ?? '';
    final roomId = value['roomId']?.toString().trim() ?? '';
    if (siteId.isEmpty || roomId.isEmpty) return null;
    return LiveNotificationTarget(siteId: siteId, roomId: roomId);
  }
}

typedef LiveNotificationTargetHandler = FutureOr<void> Function(
  LiveNotificationTarget target,
);

class OhosNotificationTargetBridge {
  OhosNotificationTargetBridge({
    required MethodChannel channel,
    required LiveNotificationTargetHandler onTarget,
  })  : _channel = channel,
        _onTarget = onTarget;

  final MethodChannel _channel;
  final LiveNotificationTargetHandler _onTarget;
  Future<void> _transition = Future<void>.value();
  bool _bound = false;

  void bind() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'notificationTargetChanged') {
      await consumePendingTarget();
    }
  }

  Future<void> consumePendingTarget() {
    _transition = _transition.then((_) async {
      try {
        final value = await _channel.invokeMethod<Object?>(
          'consumeNotificationTarget',
        );
        final target = LiveNotificationTarget.tryParse(value);
        if (target != null) {
          await _onTarget(target);
        }
      } catch (e) {
        Log.d('读取鸿蒙通知跳转目标失败: $e');
      }
    });
    return _transition;
  }
}

class LiveNotificationService {
  LiveNotificationService._();

  static const MethodChannel _channel =
      MethodChannel("simple_live/live_notifications");
  static OhosNotificationTargetBridge? _targetBridge;

  static void bindOhosNavigation(LiveNotificationTargetHandler onTarget) {
    if (!Utils.isOhos || _targetBridge != null) return;
    final bridge = OhosNotificationTargetBridge(
      channel: _channel,
      onTarget: onTarget,
    );
    bridge.bind();
    _targetBridge = bridge;
  }

  static Future<void> consumePendingOhosTarget() async {
    await _targetBridge?.consumePendingTarget();
  }

  static Future<bool> requestPermissionIfNeeded() async {
    if (Utils.isOhos) {
      try {
        return await _channel.invokeMethod<bool>('requestPermission') ?? false;
      } catch (e) {
        Log.d("请求鸿蒙通知权限失败: $e");
        return false;
      }
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        return true;
      }
      return (await Permission.notification.request()).isGranted;
    } catch (e) {
      Log.d("请求通知权限失败: $e");
      return false;
    }
  }

  static Future<void> showLiveStart(FollowUser item) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Utils.isOhos) {
      return;
    }
    final granted = await requestPermissionIfNeeded();
    if (!granted) {
      return;
    }
    try {
      await _channel.invokeMethod<void>("showLiveStart", {
        "notificationId": item.id.hashCode & 0x7fffffff,
        "title": "${item.userName} 开播了",
        "body": "点击回到 Simple Live 查看直播",
        "roomId": item.roomId,
        "siteId": item.siteId,
      });
    } catch (e) {
      Log.d("发送开播提醒失败: $e");
    }
  }
}
