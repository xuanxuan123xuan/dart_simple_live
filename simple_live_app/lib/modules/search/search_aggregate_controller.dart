import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_aggregate_models.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Fetches the first search page for every supported site as one operation.
///
/// This controller deliberately does not use the base pagination controller:
/// search has independent per-site outcomes and no aggregate pagination.
class SearchAggregateController extends GetxController {
  SearchAggregateController({
    List<Site>? sites,
    this.timeout = const Duration(seconds: 20),
  })  : _usesConfiguredSites = sites == null,
        _sites = List<Site>.unmodifiable(sites ?? Sites.visibleSites);

  final bool _usesConfiguredSites;
  List<Site> _sites;
  final Duration timeout;

  /// The complete immutable state for the latest requested search.
  final Rx<SearchAggregateResult> result = SearchAggregateResult.empty().obs;

  int _searchVersion = 0;
  CoreCancellationToken? _activeCancellation;
  Worker? _settingsWorker;
  bool _settingsRefreshScheduled = false;
  bool _isDisposing = false;

  @override
  void onInit() {
    super.onInit();
    if (!_usesConfiguredSites) {
      return;
    }

    final settings = AppSettingsController.instance;
    _settingsWorker = everAll(
      <RxInterface<dynamic>>[
        settings.siteSort,
        settings.hiddenSiteIds,
      ],
      (_) => _scheduleSitesRefresh(),
    );
    _refreshSitesFromSettings();
  }

  void _scheduleSitesRefresh() {
    if (_settingsRefreshScheduled || isClosed || _isDisposing) {
      return;
    }
    _settingsRefreshScheduled = true;
    scheduleMicrotask(() {
      _settingsRefreshScheduled = false;
      _refreshSitesFromSettings();
    });
  }

  void _refreshSitesFromSettings() {
    if (isClosed || _isDisposing || !_usesConfiguredSites) {
      return;
    }

    final updatedSites = List<Site>.unmodifiable(Sites.visibleSites);
    if (_hasSameSiteOrder(_sites, updatedSites)) {
      return;
    }

    _sites = updatedSites;
    final query = result.value.query;
    if (query == null || query.keyword.trim().isEmpty) {
      _cancelActive('search platforms changed');
      _searchVersion++;
      result.value = SearchAggregateResult.empty();
      return;
    }

    unawaited(_search(query.keyword, query.searchMode, force: true));
  }

  bool _hasSameSiteOrder(List<Site> first, List<Site> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id) {
        return false;
      }
    }
    return true;
  }

  /// Runs room (0) or anchor (1) search concurrently for every configured site.
  ///
  /// A blank keyword clears the current aggregate state without making requests.
  /// The returned future completes when all sites complete or the total timeout
  /// expires. A new query, timeout, or controller disposal cancels the previous
  /// network operation and the version guard rejects any late completion.
  Future<void> search(String keyword, int searchMode) async {
    await _search(keyword, searchMode);
  }

  Future<void> _search(
    String keyword,
    int searchMode, {
    bool force = false,
  }) async {
    if (isClosed || _isDisposing) {
      return;
    }
    if (searchMode != 0 && searchMode != 1) {
      throw ArgumentError.value(
        searchMode,
        'searchMode',
        'Expected 0 (rooms) or 1 (anchors).',
      );
    }

    final normalizedKeyword = keyword.trim();
    final currentQuery = result.value.query;
    if (!force &&
        currentQuery?.keyword == normalizedKeyword &&
        currentQuery?.searchMode == searchMode &&
        result.value.sites.any((site) => site.isLoading)) {
      return;
    }

    _cancelActive("search replaced");
    final version = ++_searchVersion;
    if (normalizedKeyword.isEmpty) {
      result.value = SearchAggregateResult.empty();
      return;
    }

    final sitesSnapshot = List<Site>.unmodifiable(_sites);
    final query = SearchAggregateQuery(
      keyword: normalizedKeyword,
      searchMode: searchMode,
    );
    result.value = SearchAggregateResult(
      query: query,
      sites: sitesSnapshot.map(SearchAggregateSiteState.loading),
    );

    final cancellation = CoreCancellationToken();
    _activeCancellation = cancellation;
    final searches = <Future<void>>[
      for (var index = 0; index < sitesSnapshot.length; index++)
        _searchSite(
          site: sitesSnapshot[index],
          index: index,
          keyword: normalizedKeyword,
          searchMode: searchMode,
          version: version,
          cancellation: cancellation,
        ),
    ];
    final completedBeforeDeadline = await Future.any<bool>(<Future<bool>>[
      Future.wait(searches).then((_) => true),
      Future<void>.delayed(timeout).then((_) => false),
    ]);

    if (!_isCurrent(version)) {
      return;
    }
    if (!completedBeforeDeadline) {
      cancellation.cancel("aggregate search timeout");
      _markUnfinishedSitesTimedOut(version);
    }
    if (identical(_activeCancellation, cancellation)) {
      _activeCancellation = null;
    }
  }

  Future<void> _searchSite({
    required Site site,
    required int index,
    required String keyword,
    required int searchMode,
    required int version,
    required CoreCancellation cancellation,
  }) async {
    try {
      final List<Object> items;
      final LiveSearchMetadata metadata;
      if (searchMode == 0) {
        final searchResult = await site.liveSite.searchRooms(
          keyword,
          page: 1,
          cancellation: cancellation,
        );
        items = List<Object>.of(searchResult.items);
        metadata = searchResult.metadata;
      } else {
        final searchResult = await site.liveSite.searchAnchors(
          keyword,
          page: 1,
          cancellation: cancellation,
        );
        items = List<Object>.of(searchResult.items);
        metadata = searchResult.metadata;
      }
      if (_isCurrent(version) && !cancellation.isCancelled) {
        _replaceSiteState(
          version,
          index,
          SearchAggregateSiteState.data(site, items, metadata),
        );
      }
    } on CoreCancelledError {
      return;
    } catch (error) {
      if (_isCurrent(version) && !cancellation.isCancelled) {
        _replaceSiteState(
          version,
          index,
          SearchAggregateSiteState.failure(site, error),
        );
      }
    }
  }

  void _markUnfinishedSitesTimedOut(int version) {
    if (!_isCurrent(version)) {
      return;
    }

    final current = result.value;
    result.value = current.copyWith(
      sites: current.sites.map((siteState) {
        if (!siteState.isLoading) {
          return siteState;
        }
        return SearchAggregateSiteState.failure(
          siteState.site,
          TimeoutException('Aggregate search exceeded $timeout.'),
        );
      }),
    );
  }

  void _replaceSiteState(
    int version,
    int index,
    SearchAggregateSiteState replacement,
  ) {
    if (!_isCurrent(version)) {
      return;
    }

    final current = result.value;
    if (index >= current.sites.length) {
      return;
    }
    final updatedSites = List<SearchAggregateSiteState>.of(current.sites);
    updatedSites[index] = replacement;
    result.value = current.copyWith(sites: updatedSites);
  }

  bool _isCurrent(int version) =>
      !isClosed && !_isDisposing && version == _searchVersion;

  void _cancelActive([Object? reason]) {
    _activeCancellation?.cancel(reason);
    _activeCancellation = null;
  }

  @override
  void onClose() {
    _isDisposing = true;
    _settingsWorker?.dispose();
    _settingsWorker = null;
    _cancelActive("aggregate search closed");
    _searchVersion++;
    super.onClose();
  }
}
