import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

class _PassportProtocolMock extends Interceptor {
  _PassportProtocolMock({this.confirmationLocation = '/scan/confirm'});

  final String confirmationLocation;
  int pollCount = 0;
  final requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final path = options.uri.path;
    if (path == '/lapi/did/api/get') {
      handler.resolve(_response(
        options,
        {
          'data': {'did': 'device-1'}
        },
        setCookies: const ['dy_did=device-1; Domain=.douyu.com; Path=/'],
      ));
      return;
    }
    if (path == '/scan/generateCode') {
      handler.resolve(_response(
        options,
        {
          'error': 0,
          'data': {'url': 'https://m.douyu.com/scan/code', 'code': 'code-1'}
        },
      ));
      return;
    }
    if (path == '/japi/scan/auth') {
      pollCount++;
      if (pollCount == 1) {
        handler.resolve(_response(options, {'error': -2}));
      } else {
        handler.resolve(_response(options, {
          'error': 0,
          'data': {'url': confirmationLocation},
        }));
      }
      return;
    }
    if (path == '/scan/confirm') {
      handler.resolve(_response(
        options,
        {'error': 0},
        setCookies: const [
          'LTP0=refresh-1; Domain=.douyu.com; Path=/',
          'acf_auth=auth-1; Domain=.douyu.com; Path=/',
          'acf_uid=42; Domain=.douyu.com; Path=/',
        ],
      ));
      return;
    }
    handler.reject(DioException(
      requestOptions: options,
      error: StateError('unexpected passport request: $path'),
    ));
  }

  Response<String> _response(
    RequestOptions options,
    Map<String, dynamic> body, {
    List<String> setCookies = const [],
  }) =>
      Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: jsonEncode(body),
        headers: Headers.fromMap(
          setCookies.isEmpty ? const {} : {'set-cookie': setCookies},
        ),
      );
}

void main() {
  test('passport starts without credentials and close is idempotent', () {
    final passport = DouyuPassport();
    expect(passport.did, isEmpty);
    expect(passport.ltp0, isEmpty);
    passport.close();
    passport.close();
    expect(passport.did, isEmpty);
  });

  test('runs the QR protocol against an injected mock and keeps auth cookies',
      () async {
    final protocol = _PassportProtocolMock();
    final dio = Dio()..interceptors.add(protocol);
    final passport = DouyuPassport(dio: dio);

    expect(await passport.generateQrCode(), 'https://m.douyu.com/scan/code');
    expect(await passport.poll(), DouyuQrStatus.waiting);
    expect(await passport.poll(), DouyuQrStatus.authorized);
    expect(passport.did, 'device-1');
    expect(passport.ltp0, 'refresh-1');
    expect(passport.hasAuthenticatedSession, isTrue);
    expect(passport.cookie, contains('acf_auth=auth-1'));
    expect(
        protocol.requests
            .every((request) => request.uri.host == 'passport.douyu.com'),
        isTrue);
  });

  test('rejects a confirmation redirect outside the passport host', () async {
    final protocol = _PassportProtocolMock(
      confirmationLocation: 'https://evil.example/steal',
    );
    final dio = Dio()..interceptors.add(protocol);
    final passport = DouyuPassport(dio: dio);
    await passport.generateQrCode();

    expect(
      () => passport.poll(),
      throwsA(isA<CoreError>()),
    );
  });
}
