import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class CategoryListController extends BasePageController<AppLiveCategory> {
  final Site site;
  bool _hasLoadedOnce = false;
  StreamSubscription<List<LiveCategory>>? _kuaishouUpdates;
  CategoryListController(this.site) {
    final liveSite = site.liveSite;
    if (liveSite is KuaishouSite) {
      _kuaishouUpdates = liveSite.categoryUpdates.listen((categories) {
        list.assignAll(categories.map(AppLiveCategory.fromLiveCategory));
      });
    }
  }

  @override
  Future<List<AppLiveCategory>> getData(int page, int pageSize) async {
    var result = await site.liveSite.getCategores();
    _hasLoadedOnce = true;
    return result.map((e) => AppLiveCategory.fromLiveCategory(e)).toList();
  }

  @override
  bool hasMoreForPage({
    required List<AppLiveCategory> items,
    required int page,
    required int pageSize,
  }) {
    return false;
  }

  @override
  Future refreshData() async {
    if (!_hasLoadedOnce || site.liveSite is! KuaishouSite) {
      return super.refreshData();
    }
    try {
      loadding = true;
      final result = await (site.liveSite as KuaishouSite).refreshCategories();
      list.assignAll(result.map(AppLiveCategory.fromLiveCategory));
    } catch (error) {
      handleError(error, showPageError: list.isEmpty);
    } finally {
      loadding = false;
      pageLoadding.value = false;
    }
  }

  @override
  void onClose() {
    _kuaishouUpdates?.cancel();
    super.onClose();
  }
}

class AppLiveCategory extends LiveCategory {
  var showAll = false.obs;
  AppLiveCategory({
    required super.id,
    required super.name,
    required super.children,
  }) {
    showAll.value = children.length < 19;
  }

  List<LiveSubCategory> get take15 => children.take(15).toList();

  factory AppLiveCategory.fromLiveCategory(LiveCategory item) {
    return AppLiveCategory(
      children: item.children,
      id: item.id,
      name: item.name,
    );
  }
}
