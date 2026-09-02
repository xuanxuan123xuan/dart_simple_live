import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_view.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';

class HomePage extends GetView<HomeController> {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
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
              return Padding(
                // The compact selector is centered in the space left of the
                // search action, so its fixed icon slots cannot be occluded.
                padding: compact
                    ? const EdgeInsets.only(left: 12, right: 64)
                    : const EdgeInsets.symmetric(horizontal: 64),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SiteGlassTabBar(
                      controller: controller.tabController,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GlassSurface(
              role: GlassSurfaceRole.navigation,
              radius: 22,
              liveBackdrop: true,
              child: IconButton(
                onPressed: controller.toSearch,
                icon: const Icon(Icons.search),
              ),
            ),
          )
        ],
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
