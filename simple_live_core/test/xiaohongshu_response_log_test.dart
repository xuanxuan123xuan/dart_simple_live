import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/custom_interceptor.dart';
import 'package:test/test.dart';

void main() {
  test('XHS opt-in hides whole response JSON or SSR from logs', () {
    final messages = <String>[];
    final previous = CoreLog.onPrintLog;
    final previousType = CoreLog.requestLogType;
    CoreLog.onPrintLog = (_, message) => messages.add(message);
    CoreLog.requestLogType = RequestLogType.all;
    try {
      final options = RequestOptions(
          path: 'https://www.xiaohongshu.com/livestream/570493541297105186',
          extra: {
            'ts': DateTime.now().millisecondsSinceEpoch,
            'redactResponse': true
          });
      CustomInterceptor().onResponse(
          Response(
              requestOptions: options,
              statusCode: 200,
              data: '<script>private-response-value</script>'),
          ResponseInterceptorHandler());
      expect(messages.join(), isNot(contains('private-response-value')));
      expect(messages.join(), contains('Response Data：<redacted>'));
      messages.clear();
      options.extra['redactResponse'] = false;
      CustomInterceptor().onResponse(
          Response(
              requestOptions: options,
              statusCode: 200,
              data: 'public-response-value'),
          ResponseInterceptorHandler());
      expect(messages.join(), contains('public-response-value'));
    } finally {
      CoreLog.onPrintLog = previous;
      CoreLog.requestLogType = previousType;
    }
  });
}
