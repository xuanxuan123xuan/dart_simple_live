import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/modules/category/category_controller.dart';
import 'package:simple_live_app/modules/category/category_list_view.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';

class CategoryPage extends GetView<CategoryController> {
  const CategoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScope(
      child: Obx(() {
        final tabs = controller.tabs;
        final scaffoldBackground = Theme.of(context).scaffoldBackgroundColor;
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            forceMaterialTransparency: true,
            title: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SiteGlassTabBar(
                  controller: tabs.controller,
                  sites: tabs.sites,
                ),
              ),
            ),
          ),
          body: GlassBackgroundSource(
            child: ColoredBox(
              color: scaffoldBackground,
              child: TabBarView(
                controller: tabs.controller,
                children: tabs.sites
                    .map(
                      (e) => CategoryListView(
                        e.id,
                        key: ValueKey(e.id),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      }),
    );
  }
}
