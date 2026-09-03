import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/modules/follow_user/tv_follow_grid_layout.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/current_room_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/card/anchor_card.dart';

class FollowUserPage extends StatefulWidget {
  const FollowUserPage({super.key});

  @override
  State<FollowUserPage> createState() => _FollowUserPageState();
}

class _FollowUserPageState extends State<FollowUserPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, AppFocusNode> _focusNodes = <String, AppFocusNode>{};
  final AppFocusNode _pageFocusNode = AppFocusNode();
  final AppFocusNode _backFocusNode = AppFocusNode();
  final AppFocusNode _searchFocusNode = AppFocusNode();
  final AppFocusNode _displayFocusNode = AppFocusNode();
  final AppFocusNode _refreshAllFocusNode = AppFocusNode();
  final AppFocusNode _previousPageFocusNode = AppFocusNode();
  final AppFocusNode _nextPageFocusNode = AppFocusNode();
  final AppFocusNode _refreshPageFocusNode = AppFocusNode();
  _TvFollowLayoutSpec? _currentLayout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_enterPage());
    });
  }

  @override
  void dispose() {
    FollowUserService.instance.onFollowPageExited();
    _scrollController.dispose();
    _pageFocusNode.dispose();
    _backFocusNode.dispose();
    _searchFocusNode.dispose();
    _displayFocusNode.dispose();
    _refreshAllFocusNode.dispose();
    _previousPageFocusNode.dispose();
    _nextPageFocusNode.dispose();
    _refreshPageFocusNode.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    super.dispose();
  }

  Future<void> _enterPage() async {
    await FollowUserService.instance.onFollowPageEntered();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInitialItem());
  }

  AppFocusNode _focusNodeFor(String key) {
    return _focusNodes.putIfAbsent(key, AppFocusNode.new);
  }

  _TvFollowLayoutSpec _layoutSpec({
    required double availableWidth,
    required double availableHeight,
  }) {
    final style = AppSettingsController.instance.followDisplayStyle.value;
    final showLiveCover =
        AppSettingsController.instance.followShowLiveCover.value;
    if (style == "compact") {
      return _TvFollowLayoutSpec(
        displayStyle: AnchorCardDisplayStyle.compact,
        crossAxisCount: 4,
        mainAxisExtent: showLiveCover ? 178.w : 118.w,
        mainAxisSpacing: showLiveCover ? 20.w : 16.w,
        crossAxisSpacing: 24.w,
      );
    }
    if (style == "card") {
      final spacing = 24.w;
      final resolved = TvFollowGridLayout.resolve(
        availableWidth: availableWidth - 96.w,
        availableHeight: availableHeight -
            (FollowUserService.instance.paginationEnabled.value
                ? 120.w
                : 24.w),
        density: AppSettingsController.instance.followCardDensity.value,
        showLiveCover: showLiveCover,
        crossAxisSpacing: spacing,
        mainAxisSpacing: 20.w,
        detailsExtent: TvFollowGridLayout.cardDetailsExtent.w,
        avatarMinimumExtent: 168.w,
        avatarMaximumExtent: 230.w,
      );
      return _TvFollowLayoutSpec(
        displayStyle: AnchorCardDisplayStyle.card,
        crossAxisCount: resolved.crossAxisCount,
        mainAxisExtent: resolved.mainAxisExtent,
        mainAxisSpacing: 20.w,
        crossAxisSpacing: spacing,
      );
    }
    return _TvFollowLayoutSpec(
      displayStyle: AnchorCardDisplayStyle.defaultList,
      crossAxisCount: 3,
      mainAxisExtent: showLiveCover ? 210.w : 140.w,
      mainAxisSpacing: showLiveCover ? 24.w : 18.w,
      crossAxisSpacing: 28.w,
    );
  }

  void _focusInitialItem() {
    final items = FollowUserService.instance.list;
    if (items.isEmpty) {
      _backFocusNode.requestFocus();
      return;
    }
    final currentKey = CurrentRoomService.instance.currentKey;
    final index = currentKey.isEmpty
        ? 0
        : items.indexWhere(
            (item) => "${item.siteId}_${item.roomId}" == currentKey,
          );
    _focusItemAt(index < 0 ? 0 : index, animated: false);
  }

  void _focusItemAt(int index, {bool animated = true}) {
    final items = FollowUserService.instance.list;
    if (index < 0 || index >= items.length) return;
    final node = _focusNodeFor(items[index].id);
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: animated ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _moveGridFocus(int index, int rowDelta, int columnDelta) {
    final layout = _currentLayout;
    final items = FollowUserService.instance.list;
    if (layout == null || index < 0 || index >= items.length) {
      return KeyEventResult.ignored;
    }
    final columns = layout.crossAxisCount;
    final row = index ~/ columns;
    final column = index % columns;
    if (rowDelta < 0 && row == 0) {
      final ratio = columns <= 1 ? 0.0 : column / (columns - 1);
      if (ratio < 0.2) {
        _backFocusNode.requestFocus();
      } else if (ratio < 0.45) {
        _searchFocusNode.requestFocus();
      } else if (ratio < 0.75) {
        _displayFocusNode.requestFocus();
      } else {
        _refreshAllFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (columnDelta < 0 && column == 0 ||
        columnDelta > 0 && column == columns - 1) {
      return KeyEventResult.ignored;
    }
    final target = index + rowDelta * columns + columnDelta;
    if (target < 0 || target >= items.length) {
      if (rowDelta > 0 &&
          FollowUserService.instance.paginationEnabled.value) {
        _nextPageFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    _focusItemAt(target);
    return KeyEventResult.handled;
  }

  KeyEventResult _moveTopBarFocus(AppFocusNode target) {
    target.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _keepTopBarFocus() {
    return KeyEventResult.handled;
  }

  KeyEventResult _moveTopBarToGrid() {
    if (FollowUserService.instance.list.isEmpty) {
      return KeyEventResult.handled;
    }
    _focusItemAt(0);
    return KeyEventResult.handled;
  }

  KeyEventResult _movePaginationBarFocus(AppFocusNode target) {
    target.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _movePaginationBarToGrid() {
    final layout = _currentLayout;
    final items = FollowUserService.instance.list;
    if (layout == null || items.isEmpty) {
      return KeyEventResult.handled;
    }
    final columns = layout.crossAxisCount;
    final lastRow = (items.length - 1) ~/ columns;
    _focusItemAt(lastRow * columns);
    return KeyEventResult.handled;
  }

  void _pruneFocusNodes(Iterable<FollowUser> items) {
    final activeKeys = items.map((item) => item.id).toSet();
    final staleKeys = _focusNodes.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      _focusNodes.remove(key)?.dispose();
    }
  }

  KeyEventResult _handleShortcutKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !FollowUserService.instance.paginationEnabled.value) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final altPressed = HardwareKeyboard.instance.isAltPressed;
    if (key == LogicalKeyboardKey.pageDown ||
        (altPressed && key == LogicalKeyboardKey.arrowRight)) {
      _changePage(FollowUserService.instance.goToNextPage);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp ||
        (altPressed && key == LogicalKeyboardKey.arrowLeft)) {
      _changePage(FollowUserService.instance.goToPreviousPage);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Focus(
        autofocus: true,
        focusNode: _pageFocusNode,
        onKeyEvent: _handleShortcutKey,
        child: Column(
          children: [
            AppStyle.vGap32,
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppStyle.hGap48,
                HighlightButton(
                  focusNode: _backFocusNode,
                  iconData: Icons.arrow_back,
                  text: "返回",
                  onTap: Get.back,
                  onUpKey: () => _keepTopBarFocus(),
                  onLeftKey: () => _keepTopBarFocus(),
                  onRightKey: () => _moveTopBarFocus(_searchFocusNode),
                  onDownKey: () => _moveTopBarToGrid(),
                ),
                AppStyle.hGap24,
                Text(
                  "我的关注",
                  style: AppStyle.titleStyleWhite.copyWith(
                    fontSize: 36.w,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                AppStyle.hGap24,
                HighlightButton(
                  focusNode: _searchFocusNode,
                  iconData: Icons.search,
                  text: "搜索",
                  onTap: _showSearchDialog,
                  onUpKey: () => _keepTopBarFocus(),
                  onLeftKey: () => _moveTopBarFocus(_backFocusNode),
                  onRightKey: () => _moveTopBarFocus(_displayFocusNode),
                  onDownKey: () => _moveTopBarToGrid(),
                ),
                AppStyle.hGap16,
                HighlightButton(
                  focusNode: _displayFocusNode,
                  iconData: Icons.tune,
                  text: "显示/筛选",
                  onTap: _showDisplayDialog,
                  onUpKey: () => _keepTopBarFocus(),
                  onLeftKey: () => _moveTopBarFocus(_searchFocusNode),
                  onRightKey: () => _moveTopBarFocus(_refreshAllFocusNode),
                  onDownKey: () => _moveTopBarToGrid(),
                ),
                const Spacer(),
                HighlightButton(
                  focusNode: _refreshAllFocusNode,
                  iconData: Icons.sync,
                  text: "刷新全部",
                  onTap: FollowUserService.instance.refreshAllStatus,
                  onUpKey: () => _keepTopBarFocus(),
                  onLeftKey: () => _moveTopBarFocus(_displayFocusNode),
                  onRightKey: () => _keepTopBarFocus(),
                  onDownKey: () => _moveTopBarToGrid(),
                ),
                AppStyle.hGap24,
                AppStyle.hGap48,
              ],
            ),
            Obx(() => _buildActiveFilterBar()),
            Obx(() => _buildRefreshProgress()),
            AppStyle.vGap24,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Obx(() {
                      final layout = _layoutSpec(
                        availableWidth: constraints.maxWidth,
                        availableHeight: constraints.maxHeight,
                      );
                      _currentLayout = layout;
                      final items = FollowUserService.instance.list.toList();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _pruneFocusNodes(items);
                        unawaited(
                          FollowUserService.instance
                              .refreshVisiblePreviews(items),
                        );
                      });
                      return FocusTraversalGroup(
                        child: GridView.builder(
                          controller: _scrollController,
                          primary: false,
                          cacheExtent: 1200.w,
                          padding: EdgeInsets.only(
                            left: 48.w,
                            right: 48.w,
                            bottom: FollowUserService
                                    .instance.paginationEnabled.value
                                ? 120.w
                                : 24.w,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: layout.crossAxisCount,
                            crossAxisSpacing: layout.crossAxisSpacing,
                            mainAxisSpacing: layout.mainAxisSpacing,
                            mainAxisExtent: layout.mainAxisExtent,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _buildFollowCard(
                            items[i],
                            i,
                            layout,
                          ),
                        ),
                      );
                    }),
                    Obx(
                      () => FollowUserService.instance.paginationEnabled.value
                          ? Positioned(
                              left: 48.w,
                              right: 48.w,
                              bottom: 24.w,
                              child: _buildFloatingPaginationBar(),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowCard(
    FollowUser item,
    int index,
    _TvFollowLayoutSpec layout,
  ) {
    final isCurrent = "${item.siteId}_${item.roomId}" ==
        CurrentRoomService.instance.currentKey;
    return AnchorCard(
      face: item.face,
      name: item.userName,
      roomTitle: item.roomTitle,
      roomCover: item.roomCover,
      siteId: item.siteId,
      liveStatus: item.liveStatus.value,
      roomId: item.roomId,
      playing: isCurrent,
      showLiveCover: AppSettingsController.instance.followShowLiveCover.value,
      displayStyle: layout.displayStyle,
      focusNode: _focusNodeFor(item.id),
      onLeftKey: () => _moveGridFocus(index, 0, -1),
      onRightKey: () => _moveGridFocus(index, 0, 1),
      onUpKey: () => _moveGridFocus(index, -1, 0),
      onDownKey: () => _moveGridFocus(index, 1, 0),
      onLongPress: () => unawaited(_showCardActions(item, index)),
      onTap: () async {
        final resolved =
            await FollowUserService.instance.resolveFollowBeforeEnter(item);
        final site = Sites.allSites[resolved.siteId];
        if (site == null) return;
        AppNavigator.toLiveRoomDetail(site: site, roomId: resolved.roomId);
      },
    );
  }

  Future<void> _showCardActions(FollowUser item, int originalIndex) async {
    final specialFocusNode = AppFocusNode();
    final removeFocusNode = AppFocusNode();
    try {
      await Utils.showSystemRightDialog(
        width: 620.w,
        child: Padding(
          padding: AppStyle.edgeInsetsA24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.userName, style: AppStyle.titleStyleWhite),
              AppStyle.vGap24,
              HighlightButton(
                focusNode: specialFocusNode,
                autofocus: true,
                iconData:
                    item.isSpecialFollow ? Icons.star : Icons.star_border,
                text: item.isSpecialFollow ? "取消特别关注" : "设为特别关注",
                onTap: () async {
                  await FollowUserService.instance.toggleSpecialFollow(item);
                  Get.back();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final index = FollowUserService.instance.list
                        .indexWhere((candidate) => candidate.id == item.id);
                    _focusItemAt(index < 0 ? originalIndex : index);
                  });
                },
              ),
              AppStyle.vGap16,
              HighlightButton(
                focusNode: removeFocusNode,
                iconData: Icons.person_remove_outlined,
                text: "取消关注",
                onTap: () {
                  Get.back();
                  unawaited(_removeFollowAndRestoreFocus(item, originalIndex));
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      specialFocusNode.dispose();
      removeFocusNode.dispose();
    }
  }

  Future<void> _removeFollowAndRestoreFocus(
    FollowUser item,
    int originalIndex,
  ) async {
    final removed = await FollowUserService.instance.removeItem(
      item,
      refresh: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!removed) {
        final index = FollowUserService.instance.list
            .indexWhere((candidate) => candidate.id == item.id);
        if (index >= 0) _focusItemAt(index);
        return;
      }
      final length = FollowUserService.instance.list.length;
      if (length == 0) {
        _backFocusNode.requestFocus();
      } else {
        _focusItemAt(originalIndex.clamp(0, length - 1).toInt());
      }
    });
  }

  Widget _buildActiveFilterBar() {
    final settings = AppSettingsController.instance;
    final labels = <String>[
      "样式：${_displayStyleLabel(settings.followDisplayStyle.value)}",
      if (settings.followDisplayStyle.value == "card")
        "密度：${_densityLabel(settings.followCardDensity.value)}",
      if (settings.followOnlyLive.value) "仅显示开播",
      if (settings.followRefreshOnEnter.value) "进入关注页自动刷新（首页始终刷新）",
      if (FollowUserService.instance.searchKeyword.value.isNotEmpty)
        "搜索：${FollowUserService.instance.searchKeyword.value}",
    ];
    if (labels.length == 1 &&
        labels.first ==
            "样式：${_displayStyleLabel(settings.followDisplayStyle.value)}") {
      return Padding(
        padding: EdgeInsets.only(top: 16.w, left: 48.w, right: 48.w),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            labels.first,
            style: AppStyle.subTextStyleWhite,
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: 16.w, left: 48.w, right: 48.w),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 10.w,
          runSpacing: 10.w,
          children: labels
              .map(
                (label) => Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.w),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(label, style: AppStyle.subTextStyleWhite),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _displayStyleLabel(String value) {
    switch (value) {
      case "compact":
        return "紧凑";
      case "card":
        return "卡片";
      default:
        return "默认";
    }
  }

  String _densityLabel(TvFollowCardDensity value) {
    return switch (value) {
      TvFollowCardDensity.auto => "自动三排",
      TvFollowCardDensity.comfortable => "舒适",
      TvFollowCardDensity.dense => "高密",
    };
  }

  Future<void> _showSearchDialog() async {
    final result = await Utils.showEditTextDialog(
      FollowUserService.instance.searchKeyword.value,
      title: "搜索主播",
      hintText: "只按主播名字本地搜索",
      confirm: "搜索",
      validate: (_) => true,
    );
    if (result == null) {
      return;
    }
    FollowUserService.instance.setSearchKeyword(result);
  }

  void _showDisplayDialog() {
    Utils.showSystemRightDialog(
      width: 760.w,
      child: Obx(
        () => ListView(
          padding: AppStyle.edgeInsetsA24,
          children: [
            Text("显示与筛选", style: AppStyle.titleStyleWhite),
            AppStyle.vGap24,
            Text(
              "显示样式",
              style: AppStyle.titleStyleWhite.copyWith(fontSize: 26.w),
            ),
            AppStyle.vGap16,
            Wrap(
              spacing: 16.w,
              runSpacing: 16.w,
              children: [
                _buildStyleButton("default", "默认"),
                _buildStyleButton("compact", "紧凑"),
                _buildStyleButton("card", "卡片"),
              ],
            ),
            if (AppSettingsController.instance.followDisplayStyle.value ==
                "card") ...[
              AppStyle.vGap32,
              Text(
                "卡片密度",
                style: AppStyle.titleStyleWhite.copyWith(fontSize: 26.w),
              ),
              AppStyle.vGap16,
              Wrap(
                spacing: 16.w,
                runSpacing: 16.w,
                children: [
                  _buildDensityButton(TvFollowCardDensity.auto),
                  _buildDensityButton(TvFollowCardDensity.comfortable),
                  _buildDensityButton(TvFollowCardDensity.dense),
                ],
              ),
            ],
            AppStyle.vGap32,
            Text(
              "直播封面",
              style: AppStyle.titleStyleWhite.copyWith(fontSize: 26.w),
            ),
            AppStyle.vGap16,
            _buildToggleButton(
              label: AppSettingsController.instance.followShowLiveCover.value
                  ? "展示直播封面：开"
                  : "展示直播封面：关",
              onTap: () {
                FollowUserService.instance.setShowLiveCover(
                  !AppSettingsController.instance.followShowLiveCover.value,
                );
              },
            ),
            AppStyle.vGap32,
            Text(
              "筛选",
              style: AppStyle.titleStyleWhite.copyWith(fontSize: 26.w),
            ),
            AppStyle.vGap16,
            _buildToggleButton(
              label: AppSettingsController.instance.followOnlyLive.value
                  ? "仅显示开播：开"
                  : "仅显示开播：关",
              onTap: () {
                FollowUserService.instance.setOnlyLive(
                  !AppSettingsController.instance.followOnlyLive.value,
                );
              },
            ),
            AppStyle.vGap16,
            _buildToggleButton(
              label: FollowUserService.instance.searchKeyword.value.isEmpty
                  ? "清除搜索：当前无关键字"
                  : "清除搜索：${FollowUserService.instance.searchKeyword.value}",
              onTap: FollowUserService.instance.clearSearchKeyword,
            ),
            AppStyle.vGap32,
            Text(
              "自动刷新",
              style: AppStyle.titleStyleWhite.copyWith(fontSize: 26.w),
            ),
            AppStyle.vGap16,
            Text(
              "开启后，进入关注页会先显示本地列表，再异步发起一次全量刷新；首页关注区始终会后台刷新。关注过多时，极其容易触发抖音限制。",
              style: AppStyle.subTextStyleWhite,
            ),
            AppStyle.vGap16,
            _buildToggleButton(
              label: AppSettingsController.instance.followRefreshOnEnter.value
                  ? "进入关注页后自动刷新：开"
                  : "进入关注页后自动刷新：关",
              onTap: () async {
                final current =
                    AppSettingsController.instance.followRefreshOnEnter.value;
                if (!current) {
                  final confirmed = await Utils.showAlertDialog(
                    "开启后，每次进入关注页都会先显示本地列表，再异步发起一次全量刷新；首页关注区始终会后台刷新。关注过多时，极其容易触发抖音限制。",
                    title: "风险提示",
                    confirm: "继续开启",
                  );
                  if (!confirmed) {
                    return;
                  }
                }
                FollowUserService.instance.setRefreshOnEnter(!current);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleButton(String value, String label) {
    final selected =
        AppSettingsController.instance.followDisplayStyle.value == value;
    return HighlightButton(
      focusNode: AppFocusNode(),
      text: label,
      selected: selected,
      onTap: () {
        FollowUserService.instance.setDisplayStyle(value);
      },
    );
  }

  Widget _buildToggleButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return HighlightButton(
      focusNode: AppFocusNode(),
      text: label,
      onTap: onTap,
    );
  }

  Widget _buildDensityButton(TvFollowCardDensity density) {
    final settings = AppSettingsController.instance;
    return HighlightButton(
      focusNode: AppFocusNode(),
      text: _densityLabel(density),
      selected: settings.followCardDensity.value == density,
      onTap: () => settings.setFollowCardDensity(density),
    );
  }

  Widget _buildFloatingPaginationBar() {
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.w),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(160),
          borderRadius: AppStyle.radius16,
          border: Border.all(color: Colors.white24),
        ),
        child: Obx(
          () => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HighlightButton(
                focusNode: _previousPageFocusNode,
                iconData: Icons.chevron_left,
                text: "上一页",
                onTap: FollowUserService.instance.currentDisplayPage.value > 1
                    ? () => _changePage(
                          FollowUserService.instance.goToPreviousPage,
                        )
                    : null,
                onUpKey: () => _movePaginationBarToGrid(),
                onLeftKey: () => _keepTopBarFocus(),
                onRightKey: () =>
                    _movePaginationBarFocus(_nextPageFocusNode),
                onDownKey: () => _keepTopBarFocus(),
              ),
              AppStyle.hGap16,
              Text(
                "${FollowUserService.instance.currentDisplayPage.value}/${FollowUserService.instance.totalDisplayPages.value}",
                style: AppStyle.textStyleWhite.copyWith(fontSize: 28.w),
              ),
              AppStyle.hGap16,
              HighlightButton(
                focusNode: _nextPageFocusNode,
                iconData: Icons.chevron_right,
                text: "下一页",
                onTap: FollowUserService.instance.currentDisplayPage.value <
                        FollowUserService.instance.totalDisplayPages.value
                    ? () => _changePage(
                          FollowUserService.instance.goToNextPage,
                        )
                    : null,
                onUpKey: () => _movePaginationBarToGrid(),
                onLeftKey: () =>
                    _movePaginationBarFocus(_previousPageFocusNode),
                onRightKey: () =>
                    _movePaginationBarFocus(_refreshPageFocusNode),
                onDownKey: () => _keepTopBarFocus(),
              ),
              AppStyle.hGap16,
              HighlightButton(
                focusNode: _refreshPageFocusNode,
                iconData: Icons.refresh,
                text: "刷新当前页",
                onTap: FollowUserService.instance.refreshCurrentPageStatus,
                onUpKey: () => _movePaginationBarToGrid(),
                onLeftKey: () => _movePaginationBarFocus(_nextPageFocusNode),
                onRightKey: () => _keepTopBarFocus(),
                onDownKey: () => _keepTopBarFocus(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changePage(VoidCallback changePage) {
    changePage();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInitialItem());
  }

  Widget _buildRefreshProgress() {
    final progress = FollowUserService.instance.refreshProgress.value;
    if (!progress.active) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: 12.w, left: 48.w, right: 48.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.w),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(progress.automatic ? 120 : 160),
          borderRadius: AppStyle.radius16,
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.stage,
                    style: AppStyle.textStyleWhite.copyWith(fontSize: 24.w),
                  ),
                ),
                Text(
                  "${progress.resolvedCount}/${progress.total}",
                  style: AppStyle.textStyleWhite.copyWith(fontSize: 24.w),
                ),
              ],
            ),
            if (progress.detail.isNotEmpty) ...[
              AppStyle.vGap8,
              Text(
                progress.detail,
                style: AppStyle.textStyleWhite.copyWith(fontSize: 20.w),
              ),
            ],
            AppStyle.vGap12,
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.total > 0 ? progress.percent : null,
                minHeight: 8.w,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.lightGreenAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvFollowLayoutSpec {
  final AnchorCardDisplayStyle displayStyle;
  final int crossAxisCount;
  final double mainAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const _TvFollowLayoutSpec({
    required this.displayStyle,
    required this.crossAxisCount,
    required this.mainAxisExtent,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
  });
}
