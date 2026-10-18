import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';

/// Publishes a matching platform list and tab controller as one UI update.
class SiteTabs {
  SiteTabs(List<Site> sites, this.controller)
      : sites = List.unmodifiable(sites);

  final List<Site> sites;
  final TabController controller;
}

abstract class SiteTabsController extends GetxController
    with GetTickerProviderStateMixin {
  SiteTabsController() {
    final sites = Sites.visibleSites;
    _tabs = SiteTabs(
      sites,
      TabController(length: sites.length, vsync: this),
    ).obs;
  }

  late final Rx<SiteTabs> _tabs;
  final Set<TabController> _retiredControllers = {};
  Worker? _settingsWorker;

  SiteTabs get tabs => _tabs.value;
  TabController get tabController => tabs.controller;

  /// Reuse each platform's cached lists when it moves or becomes visible again.
  void ensureSiteController(Site site);

  @override
  void onInit() {
    for (final site in tabs.sites) {
      ensureSiteController(site);
    }
    final settings = AppSettingsController.instance;
    _settingsWorker = everAll(
      [settings.siteSort, settings.hiddenSiteIds],
      (_) => _syncSites(),
    );
    super.onInit();
  }

  void _syncSites() {
    final sites = Sites.visibleSites;
    final previous = tabs;
    if (listEquals(
      sites.map((site) => site.id).toList(),
      previous.sites.map((site) => site.id).toList(),
    )) {
      return;
    }
    final selectedId = previous.sites[previous.controller.index].id;
    final selectedIndex = sites.indexWhere((site) => site.id == selectedId);
    for (final site in sites) {
      ensureSiteController(site);
    }
    final next = TabController(
      length: sites.length,
      initialIndex: selectedIndex < 0 ? 0 : selectedIndex,
      vsync: this,
    );
    _retiredControllers.add(previous.controller);
    _tabs.value = SiteTabs(sites, next);
    // Existing widgets still reference the previous animation until rebuilt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiredControllers.remove(previous.controller)) {
        previous.controller.dispose();
      }
    });
  }

  @override
  void onClose() {
    _settingsWorker?.dispose();
    tabs.controller.dispose();
    for (final controller in _retiredControllers) {
      controller.dispose();
    }
    _retiredControllers.clear();
    super.onClose();
  }
}
