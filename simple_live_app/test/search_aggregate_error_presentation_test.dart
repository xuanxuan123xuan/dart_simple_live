import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/search/search_aggregate_error_presentation.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  group('SearchAggregateErrorPresentation', () {
    final authError = DouyinSearchAuthError(
      DouyinSearchAuthFailureReason.rejected,
    );

    test('offers Cookie configuration only for Douyin auth failures', () {
      expect(
        SearchAggregateErrorPresentation.offersDouyinCookieConfig(
          Constant.kDouyin,
          authError,
        ),
        isTrue,
      );
      expect(
        SearchAggregateErrorPresentation.offersDouyinCookieConfig(
          Constant.kBiliBili,
          authError,
        ),
        isFalse,
      );
      expect(
        SearchAggregateErrorPresentation.offersDouyinCookieConfig(
          Constant.kDouyin,
          CoreError('普通搜索错误', kind: CoreErrorKind.search),
        ),
        isFalse,
      );
      expect(
        SearchAggregateErrorPresentation.offersDouyinCookieConfig(
          Constant.kDouyin,
          TimeoutException('timeout'),
        ),
        isFalse,
      );
    });

    test('keeps the detailed structured error message', () {
      expect(
        SearchAggregateErrorPresentation.message(authError),
        contains('已配置 Cookie'),
      );
      expect(
        SearchAggregateErrorPresentation.message(
          TimeoutException('timeout'),
        ),
        '请求超时',
      );
    });
  });
}
