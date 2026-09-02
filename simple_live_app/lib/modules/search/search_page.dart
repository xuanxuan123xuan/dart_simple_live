import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/search/search_aggregate_controller.dart';
import 'package:simple_live_app/modules/search/search_aggregate_view.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/guide_service.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = Get.find<SearchAggregateController>();
  final linkParser = LiveRoomLinkParser();
  final guideKey = GlobalKey();
  late final TextEditingController searchController;
  late final RxInt searchMode;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final initialKeyword = args is Map ? args["keyword"]?.toString() ?? "" : "";
    final initialMode = args is Map && args["searchMode"] is int
        ? args["searchMode"] as int
        : 0;
    searchController = TextEditingController(text: initialKeyword);
    searchMode = (initialMode == 1 ? 1 : 0).obs;
    if (initialKeyword.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || controller.isClosed) {
          return;
        }
        unawaited(search());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = Get.arguments;
      if (args is Map &&
          args['guide'] == 'search' &&
          Get.isRegistered<GuideService>()) {
        final guide = Get.find<GuideService>();
        guide.startSearchGuide();
        guide.trackFocusRectFromKey(guideKey);
      }
    });
  }

  Future<void> search() async {
    if (!mounted || controller.isClosed) {
      return;
    }
    final input = searchController.text.trim();
    final extractedUrl = LiveRoomLinkParser.extractHttpUrl(input);
    if (extractedUrl.isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      final target = await linkParser.parse(extractedUrl);
      if (!mounted || controller.isClosed) {
        return;
      }
      if (target != null) {
        AppNavigator.toLiveRoomDetail(
          site: target.site,
          roomId: target.roomId,
        );
        return;
      }
      SmartDialog.showToast("无法识别此直播链接");
      return;
    }
    await controller.search(input, searchMode.value);
  }

  @override
  void dispose() {
    searchController.dispose();
    searchMode.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep search results on the normal page surface. Only the floating
      // search control needs glass; a transparent scaffold exposes the
      // app-wide decorative route gradient across the entire page.
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
          child: KeyedSubtree(
            key: guideKey,
            child: SizedBox(
              height: 48,
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
                        value: searchMode.value,
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
                        onChanged: (value) {
                          searchMode.value = value ?? 0;
                          if (searchController.text.trim().isNotEmpty) {
                            unawaited(search());
                          }
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      onSubmitted: (_) => unawaited(search()),
                      decoration: const InputDecoration(
                        hintText: "搜点什么吧",
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "搜索",
                    onPressed: () => unawaited(search()),
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Obx(
        () => SearchAggregateView(
          result: controller.result.value,
          topClearance: MediaQuery.paddingOf(context).top + 68,
        ),
      ),
    );
  }
}
