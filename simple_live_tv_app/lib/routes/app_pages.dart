// ignore_for_file: prefer_inlined_adds

import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/account/bilibili/qr_login_controller.dart';
import 'package:simple_live_tv_app/modules/account/bilibili/qr_login_page.dart';
import 'package:simple_live_tv_app/modules/agreement/agreement_page.dart';
import 'package:simple_live_tv_app/modules/category/category_controller.dart';
import 'package:simple_live_tv_app/modules/category/category_page.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_page.dart';
import 'package:simple_live_tv_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_tv_app/modules/history/history_controller.dart';
import 'package:simple_live_tv_app/modules/history/history_page.dart';
import 'package:simple_live_tv_app/modules/home/home_controller.dart';
import 'package:simple_live_tv_app/modules/home/home_page.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_controller.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_page.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/routes/live_room_route_args.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_page.dart';
import 'package:simple_live_tv_app/modules/search/anchor/search_anchor_controller.dart';
import 'package:simple_live_tv_app/modules/search/anchor/search_anchor_page.dart';
import 'package:simple_live_tv_app/modules/search/room/search_room_controller.dart';
import 'package:simple_live_tv_app/modules/search/room/search_room_page.dart';
import 'package:simple_live_tv_app/modules/settings/settings_controller.dart';
import 'package:simple_live_tv_app/modules/settings/settings_page.dart';
import 'package:simple_live_tv_app/modules/sync/sync_controller.dart';
import 'package:simple_live_tv_app/modules/sync/sync_page.dart';
import 'package:simple_live_tv_app/modules/sync/webdav/webdav_config_page.dart';
import 'package:simple_live_tv_app/modules/sync/webdav/webdav_controller.dart';
import 'package:simple_live_tv_app/modules/sync/webdav/webdav_page.dart';

import 'route_path.dart';

class AppPages {
  AppPages._();
  static final routes = [
    GetPage(
      name: RoutePath.kAgreement,
      page: () => const AgreementPage(),
    ),
    // 首页
    GetPage(
      name: RoutePath.kHome,
      page: () => const HomePage(),
      bindings: [
        BindingsBuilder.put(() => HomeController()),
      ],
    ),
    // 数据同步
    GetPage(
      name: RoutePath.kSync,
      page: () => const SyncPage(),
      bindings: [
        BindingsBuilder.put(() => SyncController()),
      ],
    ),
    GetPage(
      name: RoutePath.kWebDAV,
      page: () => const WebDavPage(),
      bindings: [
        BindingsBuilder.put(() => WebDavController()),
      ],
    ),
    GetPage(
      name: RoutePath.kWebDAVConfig,
      page: () => const WebDavConfigPage(),
    ),

    // 关注
    GetPage(
      name: RoutePath.kFollow,
      page: () => const FollowUserPage(),
    ),

    //直播间
    GetPage(
      name: RoutePath.kLiveRoomDetail,
      page: () => const LiveRoomPage(),
      binding: BindingsBuilder.put(
        () {
          final args = Get.arguments;
          if (args is LiveRoomRouteArgs) {
            return LiveRoomController(
              pSite: args.site,
              pRoomId: args.roomId,
              pDouyinSecUserId: args.douyinSecUserId,
              pXiaohongshuHostId: args.xiaohongshuHostId,
              channelContext: args.channels,
            );
          }
          return LiveRoomController(
            pSite: args as Site,
            pRoomId: Get.parameters["roomId"] ?? "",
            pDouyinSecUserId: Get.parameters["douyinSecUserId"],
            pXiaohongshuHostId: Get.parameters["xiaohongshuHostId"],
          );
        },
      ),
    ),
    // 单窗口多屏同播
    GetPage(
      name: RoutePath.kMultiRoom,
      page: () => const MultiRoomPage(),
      binding: BindingsBuilder.put(
        () => MultiRoomController(
          (Get.arguments as List<MultiRoomItem>?) ?? const <MultiRoomItem>[],
        ),
      ),
    ),
    //哔哩哔哩二维码登录
    GetPage(
      name: RoutePath.kBiliBiliQRLogin,
      page: () => const BiliBiliQRLoginPage(),
      bindings: [
        BindingsBuilder.put(() => BiliBiliQRLoginController()),
      ],
    ),
    // 设置
    GetPage(
      name: RoutePath.kSettings,
      page: () => const SettingsPage(),
      bindings: [
        BindingsBuilder.put(() => SettingsController()),
      ],
    ),
    // 历史记录
    GetPage(
      name: RoutePath.kHistory,
      page: () => const HistoryPage(),
      bindings: [
        BindingsBuilder.put(() => HistoryController()),
      ],
    ),
    //热门直播
    GetPage(
      name: RoutePath.kHotLive,
      page: () => const HotLivePage(),
      bindings: [
        BindingsBuilder.put(() => HotliveController()),
      ],
    ),
    //分类
    GetPage(
      name: RoutePath.kCategory,
      page: () => const CategoryPage(),
      bindings: [
        BindingsBuilder.put(() => CategoryController()),
      ],
    ),
    //分类
    GetPage(
      name: RoutePath.kCategoryDetail,
      page: () => const CategoryDetailPage(),
      binding: BindingsBuilder.put(
        () => CategoryDetailController(
          site: Get.arguments[0],
          subCategory: Get.arguments[1],
        ),
      ),
    ),
    // 搜索房间
    GetPage(
      name: RoutePath.kSearchRoom,
      page: () => const SearchRoomPage(),
      bindings: [
        BindingsBuilder.put(
          () => SearchRoomController(
            Get.arguments,
          ),
        ),
      ],
    ),
    // 搜索主播
    GetPage(
      name: RoutePath.kSearchAnchor,
      page: () => const SearchAnchorPage(),
      bindings: [
        BindingsBuilder.put(
          () => SearchAnchorController(
            Get.arguments,
          ),
        ),
      ],
    ),
  ];
}
