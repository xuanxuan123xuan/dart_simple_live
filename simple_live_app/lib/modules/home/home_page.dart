import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_view.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';

const double _homeTopBarCompactLeftInset = 12;
const double _homeTopBarSearchExtent = 56;
const double _homeTopBarSearchRightInset = 12;
const double _homeTopBarSelectorSearchGap = 8;

/// The transparent app bar shared by the home page's platform selector and
/// search action.
class HomeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeTopBar({
    required this.controller,
    required this.onSearch,
    this.iconOnly,
    super.key,
  });

  final TabController controller;
  final VoidCallback onSearch;
  final bool? iconOnly;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      forceMaterialTransparency: true,
      title: null,
      flexibleSpace: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            const compactRightInset = _homeTopBarSearchExtent +
                _homeTopBarSearchRightInset +
                _homeTopBarSelectorSearchGap;
            return Padding(
              // Reserve the search action and an 8px visual gap so the
              // selector cannot reach the action on narrow phone windows.
              padding: compact
                  ? const EdgeInsets.only(
                      left: _homeTopBarCompactLeftInset,
                      right: compactRightInset,
                    )
                  : const EdgeInsets.symmetric(horizontal: 64),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SiteGlassTabBar(
                    controller: controller,
                    iconOnly: iconOnly,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: _homeTopBarSearchRightInset),
          child: SizedBox.square(
            key: const ValueKey<String>('home-top-search-action'),
            dimension: _homeTopBarSearchExtent,
            child: GlassSurface(
              role: GlassSurfaceRole.navigation,
              radius: _homeTopBarSearchExtent / 2,
              liveBackdrop: true,
              fallbackBorder: true,
              showEdgeHighlight: false,
              child: IconButton(
                onPressed: onSearch,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        )
      ],
    );
  }
}

class HomePage extends GetView<HomeController> {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: HomeTopBar(
        controller: controller.tabController,
        onSearch: controller.toSearch,
      ),
      body: TabBarView(
        controller: controller.tabController,
        children: Sites.supportSites
            .map(
              (e) => HomeListView(
                e.id,
              ),
            )
            .toList(),
      ),
    );
  }
}
