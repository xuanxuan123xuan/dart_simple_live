import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';

class TvSearchPageResult<T> {
  const TvSearchPageResult({required this.items, required this.metadata});

  final List<T> items;
  final LiveSearchMetadata metadata;
}

abstract class TvSearchController<T> extends BasePageController<T> {
  TvSearchController(this.keyword);

  final String keyword;
  final RxString siteId = Constant.kBiliBili.obs;
  Site site = Sites.allSites[Constant.kBiliBili]!;

  int _queryVersion = 0;
  int? _loadingVersion;
  CoreCancellationToken? _activeCancellation;
  final RxBool paginationUnavailable = false.obs;

  Future<TvSearchPageResult<T>> getSearchData(
    Site site,
    int page,
    CoreCancellation cancellation,
  );

  @override
  Future<void> refreshData() async {
    _cancelActive("TV search replaced");
    final version = ++_queryVersion;
    currentPage = 1;
    list.clear();
    canLoadMore.value = false;
    pageEmpty.value = false;
    pageError.value = false;
    paginationUnavailable.value = false;
    await _loadPage(version, 1);
  }

  @override
  Future<void> loadData() async {
    if (loadding.value || pageEmpty.value) {
      return;
    }
    if (list.isNotEmpty && !canLoadMore.value) {
      return;
    }
    final version = _queryVersion;
    if (_loadingVersion == version) {
      return;
    }
    await _loadPage(version, currentPage);
  }

  Future<void> _loadPage(int version, int page) async {
    if (isClosed || version != _queryVersion) {
      return;
    }
    final cancellation = CoreCancellationToken();
    final requestSite = site;
    _activeCancellation = cancellation;
    _loadingVersion = version;
    loadding.value = true;
    pageLoadding.value = page == 1;
    pageError.value = false;
    try {
      final result = await getSearchData(requestSite, page, cancellation);
      if (isClosed || version != _queryVersion || cancellation.isCancelled) {
        return;
      }
      if (page == 1) {
        list.assignAll(result.items);
      } else {
        list.addAll(result.items);
      }
      paginationUnavailable.value =
          result.metadata.continuation == SearchContinuation.unknown;
      if (result.items.isNotEmpty &&
          result.metadata.continuation == SearchContinuation.more) {
        currentPage = page + 1;
        canLoadMore.value = true;
      } else {
        canLoadMore.value = false;
        pageEmpty.value = page == 1 && result.items.isEmpty;
      }
    } on CoreCancelledError {
      return;
    } catch (error) {
      if (!cancellation.isCancelled &&
          !isClosed &&
          version == _queryVersion) {
        handleError(error, showPageError: page == 1);
      }
    } finally {
      if (_loadingVersion == version) {
        _loadingVersion = null;
        loadding.value = false;
        pageLoadding.value = false;
      }
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
    }
  }

  void setSite(String id) {
    final nextSite = Sites.allSites[id];
    if (nextSite == null || (siteId.value == id && _loadingVersion != null)) {
      return;
    }
    _cancelActive("TV site changed");
    siteId.value = id;
    site = nextSite;
    refreshData();
  }

  void _cancelActive([Object? reason]) {
    _activeCancellation?.cancel(reason);
    _activeCancellation = null;
  }

  @override
  void onClose() {
    _cancelActive("TV search closed");
    _queryVersion++;
    super.onClose();
  }
}
