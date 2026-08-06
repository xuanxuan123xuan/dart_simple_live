import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/search/search_controller_base.dart';

void main() {
  test('does not write a late result from the old site into the new site',
      () async {
    final oldResult = Completer<TvSearchPageResult<int>>();
    final newSiteStarted = Completer<void>();
    final fakeSite = Site(
      id: 'search-test-site',
      name: 'test',
      logo: '',
      liveSite: LiveSite(),
      index: 99,
    );
    Sites.allSites[fakeSite.id] = fakeSite;
    final controller = _FakeTvSearchController((site, page, cancellation) {
      if (site.id == fakeSite.id) {
        newSiteStarted.complete();
        return Future<TvSearchPageResult<int>>.value(_result([2]));
      }
      return oldResult.future;
    });

    try {
      final oldLoad = controller.refreshData();
      await Future<void>.delayed(Duration.zero);

      controller.setSite(fakeSite.id);
      await newSiteStarted.future;
      await Future<void>.delayed(Duration.zero);

      oldResult.complete(_result([1]));
      await oldLoad;

      expect(controller.siteId.value, fakeSite.id);
      expect(controller.list, [2]);
    } finally {
      Sites.allSites.remove(fakeSite.id);
      controller.onClose();
    }
  });

  test('does not report a normal error after cancellation', () async {
    final requestStarted = Completer<CoreCancellation>();
    final response = Completer<TvSearchPageResult<int>>();
    final controller = _FakeTvSearchController((site, page, cancellation) {
      requestStarted.complete(cancellation);
      return response.future;
    });

    try {
      final load = controller.refreshData();
      final cancellation = await requestStarted.future;
      cancellation.cancel('test cancellation');
      response.completeError(StateError('transport completed after cancel'));
      await load;

      expect(controller.errorCount, 0);
      expect(controller.pageError.value, isFalse);
    } finally {
      controller.onClose();
    }
  });

  test('does not advance pagination when continuation is unknown', () async {
    final requestedPages = <int>[];
    final controller = _FakeTvSearchController((site, page, cancellation) {
      requestedPages.add(page);
      return Future<TvSearchPageResult<int>>.value(
        _result(
          [1],
          continuation: SearchContinuation.unknown,
        ),
      );
    });

    try {
      await controller.refreshData();
      await controller.loadData();

      expect(requestedPages, [1]);
      expect(controller.currentPage, 1);
      expect(controller.canLoadMore.value, isFalse);
      expect(controller.paginationUnavailable.value, isTrue);
    } finally {
      controller.onClose();
    }
  });
}

TvSearchPageResult<int> _result(
  List<int> items, {
  SearchContinuation continuation = SearchContinuation.done,
}) {
  return TvSearchPageResult(
    items: items,
    metadata: LiveSearchMetadata(continuation: continuation),
  );
}

class _FakeTvSearchController extends TvSearchController<int> {
  _FakeTvSearchController(this.handler) : super('keyword');

  final Future<TvSearchPageResult<int>> Function(
    Site site,
    int page,
    CoreCancellation cancellation,
  ) handler;
  int errorCount = 0;

  @override
  Future<TvSearchPageResult<int>> getSearchData(
    Site site,
    int page,
    CoreCancellation cancellation,
  ) {
    return handler(site, page, cancellation);
  }

  @override
  void handleError(Object exception, {bool showPageError = false}) {
    errorCount++;
    super.handleError(exception, showPageError: showPageError);
  }
}
