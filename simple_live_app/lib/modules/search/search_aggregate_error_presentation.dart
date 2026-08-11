import 'dart:async';

import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchAggregateErrorPresentation {
  const SearchAggregateErrorPresentation._();

  static bool offersDouyinCookieConfig(String siteId, Object? error) {
    return siteId == Constant.kDouyin && error is DouyinSearchAuthError;
  }

  static String message(Object? error) {
    if (error is TimeoutException) {
      return "请求超时";
    }
    if (error is CoreError) {
      final message = error.toString().trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
    return "加载失败";
  }
}
