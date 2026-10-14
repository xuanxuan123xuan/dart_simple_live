import 'dart:convert';

import 'live_play_quality.dart';

class LivePlayUrl {
  /// 播放地址
  final List<String> urls;

  /// 请求头
  final Map<String, String>? headers;

  /// 服务端实际返回的清晰度；无法从取流响应确认时为“清晰度未确认”。
  final LivePlayQuality? actualQuality;

  LivePlayUrl({
    required this.urls,
    this.headers,
    this.actualQuality,
  });

  @override
  String toString() {
    return json.encode({
      "urls": urls,
      "headers": headers.toString(),
      if (actualQuality != null) "actualQuality": actualQuality.toString(),
    });
  }
}
