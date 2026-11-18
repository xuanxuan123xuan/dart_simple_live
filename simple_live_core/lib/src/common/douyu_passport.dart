import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'core_error.dart';
import 'douyu_cookie_helper.dart';

enum DouyuQrStatus { waiting, scanned, expired, authorized }

/// Isolated Passport session used by the Douyu QR login flow.
class DouyuPassport {
  DouyuPassport({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
              ),
            );

  final Dio _dio;
  static final Uri _base = Uri.parse('https://passport.douyu.com/');
  static const String _passportHost = 'passport.douyu.com';
  final Map<String, Cookie> _cookies = <String, Cookie>{};
  CancelToken? _cancelToken;
  String _code = '';
  int _generation = 0;

  String get did => _cookies['dy_did']?.value ?? '';
  String get ltp0 => _cookies['ltp0']?.value ?? '';

  /// All credentials collected by the passport flow, in Cookie-header form.
  ///
  /// The previous implementation exposed only `dy_did` and `LTP0`. Those
  /// fields identify the device but do not prove that the QR flow actually
  /// authenticated an account. Keeping the complete, scoped cookie jar lets
  /// the account service verify the authenticated session before saving it.
  String get cookie => _cookies.values
      .map((value) => '${_canonicalCookieName(value.name)}=${value.value}')
      .join('; ');

  bool get hasAuthenticatedSession =>
      DouyuCookieHelper.hasAuthenticatedSession(cookie);

  Future<String> generateQrCode() async {
    close();
    final generation = _generation;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final device = await _request(
      _base.resolve('/lapi/did/api/get'),
      query: const {'client_id': '1', 'callback': 'slive_did'},
      generation: generation,
      cancelToken: cancelToken,
    );
    _assertGeneration(generation);
    final deviceId = device['data']?['did']?.toString() ?? '';
    if (deviceId.isNotEmpty) _cookies['dy_did'] = Cookie('dy_did', deviceId);
    final result = await _request(
      _base.resolve('/scan/generateCode'),
      data: const {'client_id': '1', 'isMultiAccount': '0'},
      generation: generation,
      cancelToken: cancelToken,
    );
    _assertGeneration(generation);
    final url = result['data']?['url']?.toString() ?? '';
    _code = result['data']?['code']?.toString() ?? '';
    if (result['error'] != 0 || url.isEmpty || _code.isEmpty) {
      throw CoreError('斗鱼二维码生成失败，请刷新重试');
    }
    return url;
  }

  Future<DouyuQrStatus> poll() async {
    if (_code.isEmpty) return DouyuQrStatus.expired;
    final generation = _generation;
    final cancelToken = _cancelToken;
    if (cancelToken == null) return DouyuQrStatus.expired;
    final result = await _request(
      _base.resolve('/japi/scan/auth'),
      query: {
        'code': _code,
        'time': DateTime.now().millisecondsSinceEpoch.toString(),
      },
      generation: generation,
      cancelToken: cancelToken,
    );
    _assertGeneration(generation);
    switch (result['error']) {
      case -2:
        return DouyuQrStatus.waiting;
      case 1:
        return DouyuQrStatus.scanned;
      case -1:
        return DouyuQrStatus.expired;
      case 0:
        final location = result['data']?['url']?.toString() ?? '';
        if (location.isEmpty) {
          throw CoreError('斗鱼未返回登录确认地址，请刷新二维码重试');
        }
        final confirmation = await _request(
          _base.resolve(location),
          query: const {'callback': 'appClient_json_callback'},
          generation: generation,
          cancelToken: cancelToken,
        );
        _assertGeneration(generation);
        if (confirmation['error'] != 0 ||
            did.isEmpty ||
            ltp0.isEmpty ||
            !hasAuthenticatedSession) {
          throw CoreError('斗鱼未返回有效登录凭据，请刷新二维码重试');
        }
        _code = '';
        return DouyuQrStatus.authorized;
      default:
        throw CoreError('斗鱼暂时无法确认登录，请刷新重试');
    }
  }

  void close() {
    _generation++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _cookies.clear();
    _code = '';
  }

  Future<Map<String, dynamic>> _request(
    Uri uri, {
    Map<String, String>? query,
    Map<String, String>? data,
    required int generation,
    required CancelToken cancelToken,
  }) async {
    if (query != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    for (var redirects = 0; redirects < 5; redirects++) {
      _assertGeneration(generation);
      if (uri.scheme != 'https' || uri.host != _passportHost) {
        throw CoreError('斗鱼登录地址无效');
      }
      final response = await _dio.requestUri<String>(
        uri,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          method: data == null ? 'GET' : 'POST',
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: {
            'Referer': _base.toString(),
            'Origin': 'https://passport.douyu.com',
            'User-Agent': 'Mozilla/5.0 SimpleLive',
            'Cookie': cookie,
          },
        ),
      );
      _assertGeneration(generation);
      _absorbCookies(response.headers['set-cookie']);
      final status = response.statusCode ?? 200;
      if (status >= 300) {
        final location = response.headers.value('location');
        if (location == null || location.isEmpty) {
          throw CoreError('斗鱼登录跳转失败');
        }
        uri = uri.resolve(location);
        data = null;
        continue;
      }
      var text = (response.data ?? '').trim();
      if (!text.startsWith('{')) {
        final callback =
            RegExp(r'^[\w.$]+\s*\(([\s\S]*)\)\s*;?$').firstMatch(text);
        if (callback == null) throw CoreError('斗鱼登录响应无效');
        text = callback.group(1)!;
      }
      return jsonDecode(text) as Map<String, dynamic>;
    }
    throw CoreError('斗鱼登录跳转次数过多');
  }

  void _absorbCookies(List<String>? values) {
    for (final raw in values ?? const <String>[]) {
      try {
        final cookie = Cookie.fromSetCookieValue(raw);
        if (!_cookieDomainAllowsPassport(cookie.domain)) continue;
        if (cookie.maxAge == 0 ||
            (cookie.expires != null &&
                !cookie.expires!.isAfter(DateTime.now()))) {
          _cookies.remove(cookie.name.toLowerCase());
          continue;
        }
        _cookies[cookie.name.toLowerCase()] = cookie;
      } catch (_) {
        // Ignore malformed cookies from a response that may contain others.
      }
    }
  }

  bool _cookieDomainAllowsPassport(String? domain) {
    if (domain == null || domain.trim().isEmpty) return true;
    final normalized = domain.trim().toLowerCase().replaceFirst('.', '');
    return normalized == _passportHost || normalized == 'douyu.com';
  }

  String _canonicalCookieName(String name) {
    switch (name.toLowerCase()) {
      case 'ltp0':
        return 'LTP0';
      case 'acf_jwt_token':
        return 'acf_jwt_token';
      case 'acf_auth':
        return 'acf_auth';
      case 'acf_uid':
        return 'acf_uid';
      case 'dy_did':
        return 'dy_did';
      case 'acf_did':
        return 'acf_did';
      default:
        return name;
    }
  }

  void _assertGeneration(int generation) {
    if (generation != _generation) {
      throw CoreCancelledError(cause: StateError('斗鱼二维码会话已失效'));
    }
  }
}
