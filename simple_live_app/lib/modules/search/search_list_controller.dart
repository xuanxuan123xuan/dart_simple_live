import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchListController extends BasePageController<Object> {
  SearchListController(
    this.site, {
    String keyword = "",
    int mode = 0,
  })  : keyword = keyword.trim(),
        searchMode = (mode == 1 ? 1 : 0).obs {
    searchController.text = this.keyword;
  }

  final Site site;
  final TextEditingController searchController = TextEditingController();
  final RxInt searchMode;

  String keyword;
  int _queryVersion = 0;
  int? _loadingVersion;
  CoreCancellationToken? _activeCancellation;
  final Set<String> _seenSearchKeys = <String>{};
  LiveSearchMetadata? searchMetadata;
  final RxBool paginationUnavailable = false.obs;

  @override
  void onInit() {
    super.onInit();
    if (keyword.isNotEmpty) {
      unawaited(search(query: keyword, mode: searchMode.value));
    }
  }

  /// Applies a new semantic query and starts from page one immediately.
  ///
  /// A version snapshot prevents a previous keyword or mode from writing into
  /// the current list when its network request completes late.
  Future<void> search({String? query, int? mode}) async {
    final nextKeyword = (query ?? searchController.text).trim();
    final nextMode = mode == null ? searchMode.value : (mode == 1 ? 1 : 0);
    if (nextKeyword == keyword &&
        nextMode == searchMode.value &&
        _loadingVersion == _queryVersion) {
      return;
    }
    _cancelActive("search replaced");
    keyword = nextKeyword;
    searchMode.value = nextMode;
    if (searchController.text != keyword) {
      searchController.text = keyword;
    }

    final version = ++_queryVersion;
    clear();
    if (keyword.isEmpty) {
      return;
    }

    await _loadPage(
      version: version,
      page: 1,
      query: keyword,
      mode: searchMode.value,
    );
  }

  @override
  Future<void> refreshData() {
    return search(query: keyword, mode: searchMode.value);
  }

  @override
  Future<void> loadData() async {
    if (keyword.isEmpty) {
      clear();
      return;
    }
    if (pageEmpty.value || (list.isNotEmpty && !canLoadMore.value)) {
      return;
    }

    final version = _queryVersion;
    if (_loadingVersion == version) {
      return;
    }
    await _loadPage(
      version: version,
      page: currentPage,
      query: keyword,
      mode: searchMode.value,
    );
  }

  Future<void> _loadPage({
    required int version,
    required int page,
    required String query,
    required int mode,
  }) async {
    if (!_isCurrent(version)) {
      return;
    }

    _loadingVersion = version;
    final cancellation = CoreCancellationToken();
    _activeCancellation = cancellation;
    pageError.value = false;
    pageEmpty.value = false;
    pageLoadding.value = page == 1;

    try {
      final List<Object> items;
      final LiveSearchMetadata metadata;
      if (mode == 1) {
        final result = await site.liveSite.searchAnchors(
          query,
          page: page,
          cancellation: cancellation,
        );
        items = List<Object>.of(result.items);
        metadata = result.metadata;
      } else {
        final result = await site.liveSite.searchRooms(
          query,
          page: page,
          cancellation: cancellation,
        );
        items = List<Object>.of(result.items);
        metadata = result.metadata;
      }

      if (!_isCurrent(version)) {
        return;
      }
      final uniqueItems = _filterDuplicateItems(items, mode);
      if (page == 1) {
        list.assignAll(uniqueItems);
        searchMetadata = metadata;
      } else {
        list.addAll(uniqueItems);
      }
      paginationUnavailable.value =
          metadata.continuation == SearchContinuation.unknown;
      if (metadata.continuation == SearchContinuation.more) {
        currentPage = page + 1;
        canLoadMore.value = true;
      } else {
        canLoadMore.value = false;
        if (uniqueItems.isEmpty && page == 1) {
          pageEmpty.value = true;
        }
      }
    } on CoreCancelledError {
      return;
    } catch (error) {
      if (_isCurrent(version)) {
        handleError(error, showPageError: page == 1);
      }
    } finally {
      if (_loadingVersion == version) {
        _loadingVersion = null;
        pageLoadding.value = false;
      }
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
    }
  }

  void clear() {
    currentPage = 1;
    canLoadMore.value = false;
    pageError.value = false;
    pageEmpty.value = false;
    searchMetadata = null;
    paginationUnavailable.value = false;
    _seenSearchKeys.clear();
    list.clear();
  }

  List<Object> _filterDuplicateItems(List<Object> items, int mode) {
    final uniqueItems = <Object>[];
    for (final item in items) {
      final roomId = switch (item) {
        LiveRoomItem value => value.roomId.trim(),
        LiveAnchorItem value => value.roomId.trim(),
        _ => "",
      };
      if (roomId.isEmpty) {
        uniqueItems.add(item);
        continue;
      }
      final type = mode == 1 ? "anchor" : "room";
      final key = "${site.id}:$type:$roomId";
      if (_seenSearchKeys.add(key)) {
        uniqueItems.add(item);
      }
    }
    return uniqueItems;
  }

  bool _isCurrent(int version) => !isClosed && version == _queryVersion;

  void _cancelActive([Object? reason]) {
    _activeCancellation?.cancel(reason);
    _activeCancellation = null;
  }

  @override
  void onClose() {
    _queryVersion++;
    _cancelActive("single-site search closed");
    searchController.dispose();
    scrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }
}
