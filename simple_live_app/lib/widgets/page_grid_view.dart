import 'dart:io';

import 'package:flutter/material.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_app/widgets/status/app_error_widget.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:get/get.dart';

class PageGridView extends StatelessWidget {
  final BasePageController pageController;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets? padding;
  final bool firstRefresh;
  final Function()? onLoginSuccess;
  final bool showPageLoadding;
  final double crossAxisSpacing, mainAxisSpacing;
  final int crossAxisCount;
  final bool showPCRefreshButton;
  final double? childAspectRatio;
  final double? mainAxisExtent;
  final bool useFixedGrid;
  final Widget? emptyWidget;
  /// Scrollable content rendered before the grid, under the same refresh and
  /// pagination controller. Use [SliverToBoxAdapter] for regular widgets.
  final List<Widget> headerSlivers;
  const PageGridView({
    required this.itemBuilder,
    required this.pageController,
    this.padding,
    this.firstRefresh = false,
    this.showPageLoadding = false,
    this.onLoginSuccess,
    this.crossAxisSpacing = 0.0,
    this.mainAxisSpacing = 0.0,
    this.showPCRefreshButton = true,
    this.childAspectRatio,
    this.mainAxisExtent,
    this.useFixedGrid = false,
    this.emptyWidget,
    this.headerSlivers = const [],
    required this.crossAxisCount,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical &&
                  notification.metrics.extentAfter < 280 &&
                  pageController.canLoadMore.value &&
                  !pageController.loadding) {
                pageController.loadData();
              }
              return false;
            },
            child: EasyRefresh.custom(
              header: MaterialHeader(
                completeDuration: const Duration(milliseconds: 400),
              ),
              footer: MaterialFooter(
                completeDuration: const Duration(milliseconds: 400),
              ),
              scrollController: pageController.scrollController,
              controller: pageController.easyRefreshController,
              firstRefresh: firstRefresh,
              onLoad: pageController.canLoadMore.value
                  ? pageController.loadData
                  : null,
              onRefresh: pageController.refreshData,
              slivers: _buildSlivers(),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: // 刷新按钮
                Visibility(
              visible: (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) &&
                  !pageController.pageLoadding.value &&
                  !pageController.pageEmpty.value &&
                  pageController.list.isNotEmpty &&
                  showPCRefreshButton,
              child: Center(
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Get.theme.cardColor.withAlpha(200),
                    elevation: 4,
                  ),
                  onPressed: () {
                    pageController.refreshData();
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
          Offstage(
            offstage: !(showPageLoadding && pageController.pageLoadding.value),
            child: const AppLoaddingWidget(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSlivers() {
    final slivers = List<Widget>.of(headerSlivers);

    if (pageController.pageError.value) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppErrorWidget(
            errorMsg: pageController.errorMsg.value,
            onRefresh: pageController.refreshData,
          ),
        ),
      );
      return slivers;
    }

    if (pageController.pageEmpty.value) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: emptyWidget ??
              AppEmptyWidget(onRefresh: pageController.refreshData),
        ),
      );
      return slivers;
    }

    final Widget grid = useFixedGrid
        ? SliverGrid(
            delegate: SliverChildBuilderDelegate(
              itemBuilder,
              childCount: pageController.list.length,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: crossAxisSpacing,
              mainAxisSpacing: mainAxisSpacing,
              childAspectRatio: childAspectRatio ?? 3.4,
              mainAxisExtent: mainAxisExtent,
            ),
          )
        : SliverMasonryGrid.count(
            childCount: pageController.list.length,
            itemBuilder: itemBuilder,
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

    slivers.add(
      padding == null ? grid : SliverPadding(padding: padding!, sliver: grid),
    );
    return slivers;
  }
}
