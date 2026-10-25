import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';

class HotliveController extends BasePageController<LiveRoomItemExt> {
  var siteId = Constant.kBiliBili.obs;
  var site = Sites.allSites[Constant.kBiliBili]!;
  int _siteGeneration = 0;
  int? _loadingGeneration;

  @override
  void onInit() {
    scrollController.addListener(scrollListener);
    refreshData();
    super.onInit();
  }

  void scrollListener() {
    if (scrollController.position.pixels >=
        (scrollController.position.maxScrollExtent - 100.w)) {
      loadData();
    }
  }

  Future<void> setSite(String id) async {
    if (siteId.value == id) {
      await refreshData();
      return;
    }
    site = Sites.allSites[id]!;
    siteId.value = id;
    _siteGeneration++;
    _resetListState();
    await loadData();
  }

  @override
  Future<void> refreshData() async {
    if (!tryBeginRefresh()) return;
    _siteGeneration++;
    _resetListState();
    await loadData();
  }

  void _resetListState() {
    currentPage = 1;
    canLoadMore.value = false;
    list.clear();
    pageError.value = false;
    errorMsg.value = '';
    pageEmpty.value = false;
    notLogin.value = false;
  }

  @override
  Future<void> loadData() async {
    final generation = _siteGeneration;
    if (_loadingGeneration == generation ||
        (currentPage > 1 && !canLoadMore.value)) {
      return;
    }

    final requestedPage = currentPage;
    final requestedSite = site;
    _loadingGeneration = generation;
    loadding.value = true;
    pageLoadding.value = requestedPage == 1;
    pageError.value = false;
    pageEmpty.value = false;
    notLogin.value = false;

    try {
      final result =
          await requestedSite.liveSite.getRecommendRooms(page: requestedPage);
      if (generation != _siteGeneration || isClosed) return;

      final items = result.items
          .map((item) => LiveRoomItemExt(
                roomId: item.roomId,
                title: item.title,
                cover: item.cover,
                userName: item.userName,
                online: item.online,
              ))
          .toList(growable: false);
      if (requestedPage == 1) {
        list.assignAll(items);
      } else {
        list.addAll(items);
      }
      currentPage = requestedPage + 1;
      canLoadMore.value = result.hasMore;
      pageEmpty.value = requestedPage == 1 && items.isEmpty;
    } catch (error) {
      if (generation == _siteGeneration && !isClosed) {
        handleError(error, showPageError: requestedPage == 1);
      }
    } finally {
      if (_loadingGeneration == generation) {
        _loadingGeneration = null;
        loadding.value = false;
        pageLoadding.value = false;
      }
    }
  }

  @override
  void onClose() {
    _siteGeneration++;
    scrollController.removeListener(scrollListener);
    super.onClose();
  }
}

class LiveRoomItemExt extends LiveRoomItem {
  LiveRoomItemExt({
    required super.roomId,
    required super.title,
    required super.cover,
    required super.userName,
    super.online = 0,
  });

  AppFocusNode focusNode = AppFocusNode();
}
