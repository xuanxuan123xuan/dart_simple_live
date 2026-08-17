import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/search_aggregate_controller.dart';
import 'package:simple_live_app/modules/search/search_aggregate_view.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = Get.find<SearchAggregateController>();
  final linkParser = LiveRoomLinkParser();
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: "返回",
          onPressed: Get.back,
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => unawaited(search()),
          decoration: InputDecoration(
            hintText: "搜点什么吧",
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppStyle.radius24),
            contentPadding: AppStyle.edgeInsetsH12,
            prefixIcon: Obx(
              () => DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: searchMode.value,
                  padding: AppStyle.edgeInsetsL8,
                  iconSize: 18,
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
            suffixIcon: IconButton(
              tooltip: "搜索",
              onPressed: () => unawaited(search()),
              icon: const Icon(Icons.search),
            ),
          ),
        ),
      ),
      body: Obx(
        () => SearchAggregateView(
          result: controller.result.value,
        ),
      ),
    );
  }
}
