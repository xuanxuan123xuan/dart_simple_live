import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/controller/site_tabs_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';

class HomeController extends SiteTabsController {
  StreamSubscription<dynamic>? streamSubscription;

  @override
  void onInit() {
    streamSubscription = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 0) {
          refreshOrScrollTop();
        }
      },
    );
    super.onInit();
  }

  @override
  void ensureSiteController(Site site) {
    if (!Get.isRegistered<HomeListController>(tag: site.id)) {
      Get.put(HomeListController(site), tag: site.id);
    }
  }

  void refreshOrScrollTop() {
    var tabIndex = tabController.index;
    BasePageController controller;
    controller = Get.find<HomeListController>(tag: tabs.sites[tabIndex].id);
    controller.scrollToTopOrRefresh();
  }

  void toSearch() {
    Get.toNamed(
      RoutePath.kSearch,
      arguments: {
        "siteId": tabs.sites[tabController.index].id,
      },
    );
  }

  @override
  void onClose() {
    streamSubscription?.cancel();
    super.onClose();
  }
}
