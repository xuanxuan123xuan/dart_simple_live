import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class PlatformUtils {
  static const int mobileMultiRoomMax = 4;

  PlatformUtils._();

  static bool get isOhos => Platform.operatingSystem == 'ohos';

  static bool get isMobileApp => Platform.isAndroid || Platform.isIOS || isOhos;

  /// 多开同屏所需的最小屏幕短边（逻辑像素）。
  ///
  /// 与 `live_room_page.dart` 判定 `isCompactMobile` 的阈值保持一致：短边 ≥ 600
  /// 时直播间才启用横向分栏布局，也只有这种尺寸才放得下并排的多个播放器。
  static const double multiRoomMinShortestSide = 600;

  /// 当前设备无法多开同屏时的提示文案；可以多开时返回 null。
  ///
  /// 这里是多开门禁的唯一判定入口，[supportsInlineMultiRoom] 与各处提示都由它派生，
  /// 避免"能不能开"和"为什么不能开"两套逻辑走偏。
  static String? get inlineMultiRoomUnavailableReason {
    // 多开完全基于 media_kit，而鸿蒙上 media_kit 不初始化（见 `main.dart`），
    // 播放走 video_player_ohos，因此鸿蒙暂不支持多开。
    if (isOhos) {
      return "鸿蒙版暂不支持多开同屏";
    }
    if (isMobileApp && _shortestSide < multiRoomMinShortestSide) {
      return "屏幕太小，多开同屏需要平板或桌面端";
    }
    return null;
  }

  /// 当前设备是否支持在同一窗口内多开同屏。
  ///
  /// 手机按屏幕短边判定，平板（iPad / 安卓平板）与桌面端均可多开；
  /// 在 widget 的 build 里请优先用 [supportsInlineMultiRoomOf]，它会随窗口尺寸变化重建。
  static bool get supportsInlineMultiRoom =>
      inlineMultiRoomUnavailableReason == null;

  /// [supportsInlineMultiRoom] 的响应式版本。
  ///
  /// 通过 `MediaQuery` 读取尺寸，分屏 / 悬浮窗改变窗口大小时会触发重建。
  static bool supportsInlineMultiRoomOf(BuildContext context) {
    if (isOhos) {
      return false;
    }
    if (!isMobileApp) {
      return true;
    }
    return MediaQuery.sizeOf(context).shortestSide >= multiRoomMinShortestSide;
  }

  /// 当前窗口的逻辑短边。取不到时返回 0（按不支持处理）。
  static double get _shortestSide {
    final view = ui.PlatformDispatcher.instance.implicitView;
    if (view == null) {
      return 0;
    }
    final ratio = view.devicePixelRatio;
    if (ratio <= 0) {
      return 0;
    }
    return (view.physicalSize / ratio).shortestSide;
  }
}
