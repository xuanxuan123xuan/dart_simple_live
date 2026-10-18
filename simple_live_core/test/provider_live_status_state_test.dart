import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

class _StatusResponses extends Interceptor {
  dynamic status;
  bool fail = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (fail) {
      handler.reject(DioException(
          requestOptions: options, type: DioExceptionType.connectionTimeout));
      return;
    }
    dynamic response;
    if (options.uri.host == 'm.huya.com') {
      response = 'window.HNF_GLOBAL_INIT = ${jsonEncode({
            'roomInfo': {if (status != null) 'eLiveStatus': status}
          })}</script>';
    } else if (options.uri.host.contains('bilibili.com')) {
      response = {
        'code': 0,
        'data': {if (status != null) 'live_status': status}
      };
    } else {
      response = {
        'status_code': 0,
        'data': {
          'data': [
            {if (status != null) 'status': status}
          ]
        }
      };
    }
    handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: response));
  }
}

void main() {
  late _StatusResponses responses;
  setUp(() {
    responses = _StatusResponses();
    HttpClient.instance.dio.interceptors.insert(0, responses);
  });
  tearDown(() => HttpClient.instance.dio.interceptors.remove(responses));

  for (final entry in <String, (LiveSite Function(), int, int)>{
    'Bilibili': (() => BiliBiliSite(), 1, 0),
    'Huya': (() => HuyaSite(), 2, 0),
    'Douyin': (() => DouyinSite(abogusSigner: (url, _) => url), 2, 4),
  }.entries) {
    test('${entry.key} distinguishes live, offline and unavailable state',
        () async {
      final site = entry.value.$1();
      responses.status = '${entry.value.$2}';
      expect(await site.getLiveStatusState(roomId: '123456789'),
          LiveStatusState.live);
      responses.status = entry.value.$3;
      expect(await site.getLiveStatusState(roomId: '123456789'),
          LiveStatusState.offline);
      responses.status = null;
      expect(await site.getLiveStatusState(roomId: '123456789'),
          LiveStatusState.unknown);
      responses.fail = true;
      expect(await site.getLiveStatusState(roomId: '123456789'),
          LiveStatusState.unknown);
    });
  }
}
