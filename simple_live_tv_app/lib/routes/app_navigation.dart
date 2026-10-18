import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/category/category_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/routes/route_path.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';

/// APP页面跳转封装
/// * 需要参数的页面都应使用此类
/// * 如不需要参数，可以使用Get.toNamed
class AppNavigator {
  /// 跳转至直播间
  static Future<void> toLiveRoomDetail({
    required Site site,
    required String roomId,
    String? douyinSecUserId,
    String? xiaohongshuHostId,
    bool replaceCurrentRoute = false,
  }) async {
    if (site.id == Constant.kBiliBili &&
        !BiliBiliAccountService.instance.logined.value &&
        AppSettingsController.instance.bilibiliLoginTip.value) {
      await toBiliBiliLogin();
      if (!BiliBiliAccountService.instance.logined.value) {
        SmartDialog.showToast("未完成登录");
        return;
      }
    }

    final arguments = {
      "roomId": roomId,
      if (douyinSecUserId?.isNotEmpty == true)
        "douyinSecUserId": douyinSecUserId!,
      if (xiaohongshuHostId?.isNotEmpty == true)
        "xiaohongshuHostId": xiaohongshuHostId!,
    };
    if (replaceCurrentRoute) {
      await Get.offNamed<void>(
        RoutePath.kLiveRoomDetail,
        arguments: site,
        parameters: arguments,
      );
    } else {
      await Get.toNamed<void>(
        RoutePath.kLiveRoomDetail,
        arguments: site,
        parameters: arguments,
      );
    }
  }

  /// Open a single-window multi-room route and preserve all room metadata.
  static Future<void> toMultiRoom({
    required List<MultiRoomItem> initialRooms,
    bool closeCurrentSingleRoom = false,
  }) async {
    if (initialRooms.isEmpty) {
      SmartDialog.showToast('请至少选择一个直播间');
      return;
    }
    if (closeCurrentSingleRoom && Get.isRegistered<LiveRoomController>()) {
      await Get.find<LiveRoomController>().closePlaybackSession();
    }
    final arguments = initialRooms.toList(growable: false);
    if (closeCurrentSingleRoom) {
      await Get.offNamed<void>(RoutePath.kMultiRoom, arguments: arguments);
    } else {
      await Get.toNamed<void>(RoutePath.kMultiRoom, arguments: arguments);
    }
  }

  /// 跳转至哔哩哔哩登录
  static Future toBiliBiliLogin() async {
    await Get.toNamed(RoutePath.kBiliBiliQRLogin);
  }

  /// 跳转至分类详情
  static void toCategoryDetail(
      {required Site site, required LiveSubCategoryExt category}) {
    Get.toNamed(RoutePath.kCategoryDetail, arguments: [site, category]);
  }
}
