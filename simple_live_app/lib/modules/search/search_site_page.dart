import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

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
      // Match the aggregate search page: the page stays neutral while the
      // pinned search control remains the only glass surface.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        titleSpacing: 8,
        title: GlassSurface(
          role: GlassSurfaceRole.navigation,
          radius: 22,
          liveBackdrop: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: "返回",
                onPressed: Get.back,
                icon: const Icon(Icons.arrow_back),
              ),
              Obx(
                () => DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: controller.searchMode.value,
                    isDense: true,
                    alignment: Alignment.center,
                    dropdownColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHigh
                        .withAlpha(250),
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("房间")),
                      DropdownMenuItem(value: 1, child: Text("主播")),
                    ],
                    onChanged: (value) => controller.search(mode: value ?? 0),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller.searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: const InputDecoration(
                    hintText: "搜点什么吧",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onSubmitted: (_) => controller.search(),
                ),
              ),
              IconButton(
                tooltip: "搜索",
                onPressed: controller.search,
                icon: const Icon(Icons.search),
              ),
              Padding(
                padding: AppStyle.edgeInsetsR12,
                child: Image.asset(args.site.logo, width: 24),
              ),
            ],
          ),
        ),
      ),
      body: SearchListView(
        controller: controller,
        topClearance: MediaQuery.paddingOf(context).top + 68,
      ),
    );
  }
}
