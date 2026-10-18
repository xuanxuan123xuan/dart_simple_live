import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/category/category_controller.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_controller.dart';

class CategoryDetailController extends BasePageController<LiveRoomItemExt> {
  final Site site;
  final LiveSubCategoryExt subCategory;

  final RxInt navigationRevision = 0.obs;
  final AppFocusNode backFocusNode = AppFocusNode();
  final List<CategoryDetailLevel> _levels;
  final List<FocusNode> _retiredFocusNodes = [];
  int _viewGeneration = 0;
  bool _closed = false;
  bool _focusFirstRoomAfterLoad = false;

  CategoryDetailController({
    required this.site,
    required this.subCategory,
  }) : _levels = [CategoryDetailLevel(subCategory)];

  CategoryDetailLevel get currentLevel => _levels.last;
  LiveSubCategoryExt get currentSubCategory => currentLevel.category;

  List<LiveSubCategoryExt> get currentChildren => currentLevel.children;

  bool get isCategorySelection =>
      currentChildren.isNotEmpty && !currentLevel.showingAllRooms;

  bool get isRoomView => !isCategorySelection;

  bool get canHandleBackInternally =>
      (currentChildren.isNotEmpty && currentLevel.showingAllRooms) ||
      _levels.length > 1;

  String get pageTitle =>
      currentLevel.showingAllRooms && currentChildren.isNotEmpty
          ? '${currentSubCategory.name} · 全部'
          : currentSubCategory.name;

  @override
  void onInit() {
    scrollController.addListener(scrollListener);
    super.onInit();
    if (isRoomView) {
      _focusFirstRoomAfterLoad = true;
      unawaited(loadData());
    }
  }

  @override
  void onReady() {
    super.onReady();
    if (!_closed && isCategorySelection) {
      _restorePosition(0, currentLevel.allFocusNode);
    }
  }

  void scrollListener() {
    if (!scrollController.hasClients) return;

    if (isCategorySelection) return;
    if (canLoadMore.value &&
        scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 100.w) {
      unawaited(loadData());
    }
  }

  void rememberFocus(FocusNode focusNode) {
    if (!_closed && isCategorySelection) {
      currentLevel.categoryFocusNode = focusNode;
    }
  }

  Future<void> openAllRooms() async {
    if (_closed || !isCategorySelection) return;

    _saveCurrentPosition();
    currentLevel.categoryFocusNode = currentLevel.allFocusNode;
    currentLevel.showingAllRooms = true;
    _resetVisibleRoomState();
    navigationRevision.value++;
    currentLevel.roomScrollOffset = 0;
    _focusFirstRoomAfterLoad = true;
    await loadData();
  }

  Future<void> openSubCategory(LiveSubCategoryExt category) async {
    if (_closed ||
        !isCategorySelection ||
        !currentChildren.any((item) => item.id == category.id)) {
      return;
    }

    _saveCurrentPosition();
    currentLevel.categoryFocusNode = category.focusNode;
    _levels.add(CategoryDetailLevel(category));
    _resetVisibleRoomState();
    navigationRevision.value++;

    if (isCategorySelection) {
      currentLevel.categoryFocusNode = currentLevel.allFocusNode;
      _restorePosition(
        currentLevel.categoryScrollOffset,
        currentLevel.categoryFocusNode,
      );
      return;
    }

    currentLevel.roomScrollOffset = 0;
    _focusFirstRoomAfterLoad = true;
    await loadData();
  }

  void handleBack() {
    if (_closed) return;
    if (currentChildren.isNotEmpty && currentLevel.showingAllRooms) {
      _saveCurrentPosition();
      currentLevel.showingAllRooms = false;
      _resetVisibleRoomState();
      navigationRevision.value++;
      _restorePosition(
        currentLevel.categoryScrollOffset,
        currentLevel.allFocusNode,
      );
      return;
    }

    if (_levels.length > 1) {
      _saveCurrentPosition();
      _retireFocusNodes(_levels.removeLast().ownedFocusNodes);
      _resetVisibleRoomState();
      navigationRevision.value++;
      _restorePosition(
        currentLevel.categoryScrollOffset,
        currentLevel.categoryFocusNode,
      );
      return;
    }

    Get.back();
  }

  @override
  Future<void> refreshData() async {
    if (_closed || !isRoomView || !tryBeginRefresh()) return;
    _resetVisibleRoomState();
    currentLevel.roomScrollOffset = 0;
    _focusFirstRoomAfterLoad = true;
    await loadData();
  }

  @override
  Future<void> loadData() async {
    if (_closed || !isRoomView || loadding.value) return;
    if (currentPage > 1 && !canLoadMore.value) return;

    final requestedPage = currentPage;
    final category = currentSubCategory;
    final generation = _viewGeneration;
    loadding.value = true;
    pageLoadding.value = requestedPage == 1;
    pageError.value = false;
    pageEmpty.value = false;
    notLogin.value = false;

    try {
      final response = await site.liveSite.getCategoryRooms(
        category,
        page: requestedPage,
      );
      if (!_isCurrentRequest(generation)) return;

      final items = response.items.map(_roomItem).toList(growable: false);

      if (requestedPage == 1) {
        list.assignAll(items);
      } else {
        list.addAll(items);
      }
      currentPage = requestedPage + 1;
      canLoadMore.value = response.hasMore;
      pageEmpty.value = requestedPage == 1 && items.isEmpty;

      if (requestedPage == 1 && items.isNotEmpty && _focusFirstRoomAfterLoad) {
        _focusFirstRoomAfterLoad = false;
        _restorePosition(
          currentLevel.roomScrollOffset,
          items.first.focusNode,
        );
      }
    } catch (error) {
      if (_isCurrentRequest(generation)) {
        handleError(error, showPageError: requestedPage == 1);
      }
    } finally {
      if (_isCurrentRequest(generation)) {
        loadding.value = false;
        pageLoadding.value = false;
      }
    }
  }

  LiveRoomItemExt _roomItem(LiveRoomItem item) => LiveRoomItemExt(
        roomId: item.roomId,
        title: item.title,
        cover: item.cover,
        userName: item.userName,
        online: item.online,
      );

  void _saveCurrentPosition() {
    if (scrollController.hasClients) {
      if (isCategorySelection) {
        currentLevel.categoryScrollOffset = scrollController.offset;
      } else {
        currentLevel.roomScrollOffset = scrollController.offset;
      }
    }

    if (isCategorySelection && backFocusNode.hasFocus) {
      currentLevel.categoryFocusNode = backFocusNode;
    }
  }

  void _resetVisibleRoomState() {
    _viewGeneration++;
    _focusFirstRoomAfterLoad = false;
    _retireFocusNodes(list.map((item) => item.focusNode));
    list.clear();
    currentPage = 1;
    count = 0;
    maxPage = 0;
    canLoadMore.value = false;
    pageEmpty.value = false;
    pageError.value = false;
    notLogin.value = false;
    errorMsg.value = '';
    loadding.value = false;
    pageLoadding.value = false;
  }

  bool _isCurrentRequest(int generation) =>
      !_closed && generation == _viewGeneration;

  void _restorePosition(double offset, FocusNode? focusNode) {
    final generation = _viewGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentRequest(generation)) return;
      if (scrollController.hasClients) {
        final maxExtent = scrollController.position.maxScrollExtent;
        scrollController.jumpTo(offset.clamp(0.0, maxExtent).toDouble());
      }
      // The scroll jump may bring a previously offscreen tile into the grid.
      // Wait for it to attach before requesting focus.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrentRequest(generation)) return;
        if (focusNode?.context != null) focusNode!.requestFocus();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _retireFocusNodes(Iterable<FocusNode> nodes) {
    final retired = nodes.toList(growable: false);
    if (retired.isEmpty) return;
    _retiredFocusNodes.addAll(retired);
    // Existing Focus widgets detach during the next rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_closed) return;
      for (final node in retired) {
        if (_retiredFocusNodes.remove(node)) node.dispose();
      }
    });
  }

  @override
  void onClose() {
    _closed = true;
    _viewGeneration++;
    scrollController.removeListener(scrollListener);
    for (final node in [
      backFocusNode,
      ..._levels.expand((level) => level.ownedFocusNodes),
      ...list.map((item) => item.focusNode),
      ..._retiredFocusNodes,
    ]) {
      node.dispose();
    }
    _retiredFocusNodes.clear();
    scrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }
}

class CategoryDetailLevel {
  final LiveSubCategoryExt category;
  late final List<LiveSubCategoryExt> children;
  final List<FocusNode> _ownedChildFocusNodes = [];
  bool showingAllRooms;
  double categoryScrollOffset = 0;
  double roomScrollOffset = 0;
  FocusNode? categoryFocusNode;
  final AppFocusNode allFocusNode = AppFocusNode();

  Iterable<FocusNode> get ownedFocusNodes =>
      [allFocusNode, ..._ownedChildFocusNodes];

  CategoryDetailLevel(this.category) : showingAllRooms = false {
    children = category.children
        .where((child) => child.id != category.id)
        .map((child) {
      if (child is LiveSubCategoryExt) return child;
      final converted =
          LiveSubCategoryExt.fromLiveSubCategory(child, category.site);
      void rememberOwnedNodes(LiveSubCategoryExt item) {
        _ownedChildFocusNodes.add(item.focusNode);
        for (final nested in item.children.cast<LiveSubCategoryExt>()) {
          rememberOwnedNodes(nested);
        }
      }

      rememberOwnedNodes(converted);
      return converted;
    }).toList(growable: false);
    showingAllRooms = children.isEmpty;
    categoryFocusNode = allFocusNode;
  }
}
