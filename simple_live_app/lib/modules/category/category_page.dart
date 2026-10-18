import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/category/category_controller.dart';
import 'package:simple_live_app/modules/category/category_list_view.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';

class CategoryPage extends GetView<CategoryController> {
  const CategoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tabs = controller.tabs;
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
        body: TabBarView(
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
      );
    });
  }
}
