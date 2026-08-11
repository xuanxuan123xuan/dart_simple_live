import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/search_aggregate_controller.dart';
import 'package:simple_live_app/modules/search/search_aggregate_view.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = Get.find<SearchAggregateController>();
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
        unawaited(controller.search(initialKeyword, searchMode.value));
      });
    }
  }

  void search() {
    if (!mounted || controller.isClosed) {
      return;
    }
    unawaited(controller.search(searchController.text, searchMode.value));
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
          onSubmitted: (_) => search(),
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
                    if (searchController.text.trim().isNotEmpty) search();
                  },
                ),
              ),
            ),
            suffixIcon: IconButton(
              tooltip: "搜索",
              onPressed: search,
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
