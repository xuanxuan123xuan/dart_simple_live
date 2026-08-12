import 'dart:async';

import 'package:get/get.dart';
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
  }) : _sites = List<Site>.unmodifiable(sites ?? Sites.supportSites);

  final List<Site> _sites;
  final Duration timeout;

  /// The complete immutable state for the latest requested search.
  final Rx<SearchAggregateResult> result = SearchAggregateResult.empty().obs;

  int _searchVersion = 0;
  CoreCancellationToken? _activeCancellation;

  /// Runs room (0) or anchor (1) search concurrently for every configured site.
  ///
  /// A blank keyword clears the current aggregate state without making requests.
  /// The returned future completes when all sites complete or the total timeout
  /// expires. A new query, timeout, or controller disposal cancels the previous
  /// network operation and the version guard rejects any late completion.
  Future<void> search(String keyword, int searchMode) async {
    if (isClosed) {
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
    if (currentQuery?.keyword == normalizedKeyword &&
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

    final query = SearchAggregateQuery(
      keyword: normalizedKeyword,
      searchMode: searchMode,
    );
    result.value = SearchAggregateResult(
      query: query,
      sites: _sites.map(SearchAggregateSiteState.loading),
    );

    final cancellation = CoreCancellationToken();
    _activeCancellation = cancellation;
    final searches = <Future<void>>[
      for (var index = 0; index < _sites.length; index++)
        _searchSite(
          site: _sites[index],
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

  bool _isCurrent(int version) => !isClosed && version == _searchVersion;

  void _cancelActive([Object? reason]) {
    _activeCancellation?.cancel(reason);
    _activeCancellation = null;
  }

  @override
  void onClose() {
    _cancelActive("aggregate search closed");
    _searchVersion++;
    super.onClose();
  }
}
