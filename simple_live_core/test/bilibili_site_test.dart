import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

class _PlayInfoInterceptor extends Interceptor {
  dynamic response;
  final requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.uri.path.contains('/xlive/web-room/v2/index/getRoomPlayInfo')) {
      requests.add(options);
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: response,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

LiveRoomDetail _detail() => LiveRoomDetail(
      roomId: '1939021227',
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
    );

LivePlayQuality _quality() => LivePlayQuality(quality: '原画', data: 10000);

Map<String, dynamic> _response({dynamic playUrl}) => {
      'code': 0,
      'data': {
        'playurl_info': {'playurl': playUrl},
      },
    };

Map<String, dynamic> _hevcPlayUrl() => {
      'stream': [
        {
          'format': [
            {
              'codec': [
                {
                  'base_url': '/live/stream.m3u8',
                  'url_info': [
                    {
                      'host': 'https://cdn.example',
                      'extra': '?codec=1',
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

void main() {
  late _PlayInfoInterceptor interceptor;
  late BiliBiliSite site;

  setUp(() {
    interceptor = _PlayInfoInterceptor();
    HttpClient.instance.dio.interceptors.add(interceptor);
    site = BiliBiliSite()
      ..buvid3 = 'test-buvid3'
      ..buvid4 = 'test-buvid4';
  });

  tearDown(() => HttpClient.instance.dio.interceptors.remove(interceptor));

  test('requests AVC and HEVC and reads the HEVC stream URL', () async {
    interceptor.response = _response(playUrl: _hevcPlayUrl());

    final result = await site.getPlayUrls(
      detail: _detail(),
      quality: _quality(),
    );

    expect(result.urls, ['https://cdn.example/live/stream.m3u8?codec=1']);
    expect(interceptor.requests, hasLength(1));
    expect(interceptor.requests.single.uri.queryParameters['codec'], '0,1');
  });

  test('reports a CoreError when Bilibili returns a null playurl', () async {
    interceptor.response = _response(playUrl: null);

    await expectLater(
      site.getPlayUrls(detail: _detail(), quality: _quality()),
      throwsA(isA<CoreError>()),
    );
  });

  test('reports a CoreError for empty or malformed stream structures',
      () async {
    for (final playUrl in <dynamic>[
      {'stream': <dynamic>[]},
      {
        'stream': [
          {'format': 'invalid'},
        ],
      },
    ]) {
      interceptor.response = _response(playUrl: playUrl);

      await expectLater(
        site.getPlayUrls(detail: _detail(), quality: _quality()),
        throwsA(isA<CoreError>()),
      );
    }
  });
}
