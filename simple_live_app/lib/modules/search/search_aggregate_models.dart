import 'dart:collection';

import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// The lifecycle of one platform within an aggregate search.
enum SearchAggregateSiteStatus { loading, success, empty, error }

/// Immutable request data associated with an aggregate search result.
class SearchAggregateQuery {
  const SearchAggregateQuery({
    required this.keyword,
    required this.searchMode,
  });

  final String keyword;

  /// 0 searches rooms and 1 searches anchors.
  final int searchMode;
}

/// Immutable state for one platform in an aggregate search.
class SearchAggregateSiteState {
  SearchAggregateSiteState._({
    required this.site,
    required this.status,
    Iterable<Object> items = const <Object>[],
    this.metadata,
    this.error,
  }) : items = UnmodifiableListView<Object>(List<Object>.of(items));

  factory SearchAggregateSiteState.loading(Site site) {
    return SearchAggregateSiteState._(
      site: site,
      status: SearchAggregateSiteStatus.loading,
    );
  }

  factory SearchAggregateSiteState.data(
    Site site,
    Iterable<Object> items,
    LiveSearchMetadata metadata,
  ) {
    final immutableItems = List<Object>.of(items);
    return SearchAggregateSiteState._(
      site: site,
      status: immutableItems.isEmpty
          ? SearchAggregateSiteStatus.empty
          : SearchAggregateSiteStatus.success,
      items: immutableItems,
      metadata: metadata,
    );
  }

  factory SearchAggregateSiteState.failure(Site site, Object error) {
    return SearchAggregateSiteState._(
      site: site,
      status: SearchAggregateSiteStatus.error,
      error: error,
    );
  }

  final Site site;
  final SearchAggregateSiteStatus status;
  final UnmodifiableListView<Object> items;
  final LiveSearchMetadata? metadata;
  final Object? error;

  bool get isLoading => status == SearchAggregateSiteStatus.loading;
  bool get isSuccess => status == SearchAggregateSiteStatus.success;
  bool get isEmpty => status == SearchAggregateSiteStatus.empty;
  bool get hasError => status == SearchAggregateSiteStatus.error;
}

/// Immutable snapshot exposed by the aggregate search controller.
class SearchAggregateResult {
  SearchAggregateResult({
    required this.query,
    Iterable<SearchAggregateSiteState> sites =
        const <SearchAggregateSiteState>[],
  }) : sites = UnmodifiableListView<SearchAggregateSiteState>(
          List<SearchAggregateSiteState>.of(sites),
        );

  factory SearchAggregateResult.empty() {
    return SearchAggregateResult(query: null);
  }

  final SearchAggregateQuery? query;
  final UnmodifiableListView<SearchAggregateSiteState> sites;

  SearchAggregateResult copyWith({
    SearchAggregateQuery? query,
    Iterable<SearchAggregateSiteState>? sites,
  }) {
    return SearchAggregateResult(
      query: query ?? this.query,
      sites: sites ?? this.sites,
    );
  }
}
