import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';

class SearchSiteRouteArgs {
  const SearchSiteRouteArgs({
    required this.site,
    required this.keyword,
    required this.searchMode,
    required this.scopeId,
  });

  factory SearchSiteRouteArgs.from(Object? raw) {
    if (raw is SearchSiteRouteArgs) {
      return raw;
    }
    if (raw is! Map) {
      throw ArgumentError('Missing single-site search arguments.');
    }

    final siteId = raw["siteId"]?.toString();
    final site = Sites.allSites[siteId];
    if (site == null) {
      throw ArgumentError.value(siteId, 'siteId', 'Unknown search site.');
    }
    final mode = raw["searchMode"] == 1 ? 1 : 0;
    final scopeId = raw["scopeId"]?.toString();
    return SearchSiteRouteArgs(
      site: site,
      keyword: raw["keyword"]?.toString().trim() ?? "",
      searchMode: mode,
      scopeId: scopeId?.isNotEmpty == true
          ? scopeId!
          : "site-${site.id}-${DateTime.now().microsecondsSinceEpoch}",
    );
  }

  final Site site;
  final String keyword;
  final int searchMode;
  final String scopeId;
}

class SearchSitePage extends StatelessWidget {
  const SearchSitePage({required this.args, Key? key}) : super(key: key);

  final SearchSiteRouteArgs args;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SearchListController>(tag: args.scopeId);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: controller.searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: "搜点什么吧",
            border: OutlineInputBorder(borderRadius: AppStyle.radius24),
            contentPadding: AppStyle.edgeInsetsH12,
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "返回",
                  onPressed: Get.back,
                  icon: const Icon(Icons.arrow_back),
                ),
                Obx(
                  () => DropdownButton<int>(
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("房间")),
                      DropdownMenuItem(value: 1, child: Text("主播")),
                    ],
                    value: controller.searchMode.value,
                    onChanged: (value) => controller.search(mode: value ?? 0),
                  ),
                ),
                AppStyle.hGap8,
              ],
            ),
            suffixIcon: IconButton(
              tooltip: "搜索",
              onPressed: controller.search,
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => controller.search(),
        ),
        actions: [
          Padding(
            padding: AppStyle.edgeInsetsR12,
            child: Image.asset(args.site.logo, width: 24),
          ),
        ],
      ),
      body: SearchListView(controller: controller),
    );
  }
}
