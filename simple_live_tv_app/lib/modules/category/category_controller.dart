import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';

class CategoryController extends BasePageController<AppLiveCategory> {
  var siteId = Constant.kBiliBili.obs;
  var site = Sites.allSites[Constant.kBiliBili]!;
  int _siteSwitchGeneration = 0;
  bool _hasLoadedOnce = false;
  StreamSubscription<List<LiveCategory>>? _kuaishouUpdates;

  @override
  void onInit() {
    _listenToKuaishouUpdates();
    refreshData();
    super.onInit();
  }

  void _listenToKuaishouUpdates() {
    _kuaishouUpdates?.cancel();
    final subscribedSite = site;
    final liveSite = subscribedSite.liveSite;
    if (liveSite is! KuaishouSite) return;
    _kuaishouUpdates = liveSite.categoryUpdates.listen((categories) {
      if (isClosed || !identical(site, subscribedSite)) return;
      list.assignAll(
        categories.map(
            (item) => AppLiveCategory.fromLiveCategory(item, subscribedSite)),
      );
    });
  }

  Future<void> setSite(String id) async {
    if (siteId.value == id) return;

    final nextSite = Sites.allSites[id]!;
    site = nextSite;
    siteId.value = id;
    _listenToKuaishouUpdates();
    currentPage = 1;
    canLoadMore.value = false;
    list.clear();
    pageError.value = false;
    errorMsg.value = "";
    pageEmpty.value = false;
    notLogin.value = false;
    await _loadCategories();
  }

  Future<void> _loadCategories({bool refreshKuaishou = false}) async {
    final generation = ++_siteSwitchGeneration;
    final requestedSite = site;
    loadding.value = true;
    pageLoadding.value = list.isEmpty;
    pageError.value = false;
    errorMsg.value = '';
    pageEmpty.value = false;
    notLogin.value = false;
    try {
      final provider = requestedSite.liveSite;
      final result = refreshKuaishou && provider is KuaishouSite
          ? await provider.refreshCategories()
          : await provider.getCategores();
      if (generation != _siteSwitchGeneration || isClosed) return;
      _hasLoadedOnce = true;
      final categories = result
          .map((item) => AppLiveCategory.fromLiveCategory(item, requestedSite))
          .toList();
      currentPage = 2;
      canLoadMore.value = false;
      pageEmpty.value = categories.isEmpty;
      list.assignAll(categories);
      if (scrollController.hasClients) scrollController.jumpTo(0);
    } catch (error) {
      if (generation != _siteSwitchGeneration || isClosed) return;
      currentPage = 1;
      handleError(error, showPageError: list.isEmpty);
    } finally {
      if (generation == _siteSwitchGeneration) {
        loadding.value = false;
        pageLoadding.value = false;
      }
    }
  }

  @override
  Future<void> loadData() => _loadCategories();

  @override
  Future<void> refreshData() async {
    if (!tryBeginRefresh()) return;
    await _loadCategories(refreshKuaishou: _hasLoadedOnce);
  }

  @override
  void onClose() {
    _siteSwitchGeneration++;
    _kuaishouUpdates?.cancel();
    super.onClose();
  }
}

class AppLiveCategory extends LiveCategory {
  var showAll = false.obs;
  final Site site;
  final List<LiveSubCategoryExt> childrenExt;
  AppLiveCategory({
    required super.id,
    required super.name,
    required super.children,
    required this.site,
  }) : childrenExt = children
            .map((e) => LiveSubCategoryExt.fromLiveSubCategory(e, site))
            .toList() {
    showAll.value = children.length < 19;
  }

  List<LiveSubCategoryExt> get take15 => childrenExt.take(15).toList();

  AppFocusNode moreFocusNode = AppFocusNode();

  factory AppLiveCategory.fromLiveCategory(LiveCategory item, Site site) {
    return AppLiveCategory(
      children: item.children,
      id: item.id,
      name: item.name,
      site: site,
    );
  }
}

class LiveSubCategoryExt extends LiveSubCategory {
  LiveSubCategoryExt({
    required super.id,
    required super.name,
    required super.parentId,
    required this.site,
    super.pic,
    super.children,
  });

  factory LiveSubCategoryExt.fromLiveSubCategory(
    LiveSubCategory category,
    Site site,
  ) {
    return LiveSubCategoryExt(
      id: category.id,
      name: category.name,
      parentId: category.parentId,
      pic: category.pic,
      children: category.children
          .map((child) => LiveSubCategoryExt.fromLiveSubCategory(child, site))
          .toList(growable: false),
      site: site,
    );
  }

  final Site site;
  AppFocusNode focusNode = AppFocusNode();
}
