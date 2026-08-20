import 'dart:async';

import 'package:simple_live_core/src/common/core_cancellation.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:dio/dio.dart';

import 'custom_interceptor.dart';

class HttpClient {
  static HttpClient? _httpUtil;

  static HttpClient get instance {
    _httpUtil ??= HttpClient();
    return _httpUtil!;
  }

  late Dio dio;
  HttpClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: 20),
        receiveTimeout: Duration(seconds: 20),
        sendTimeout: Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(CustomInterceptor());
  }

  _CancellationBinding? _bindCancellation(
    CoreCancellation? cancellation,
    CancelToken? cancel,
  ) {
    if (cancellation != null && cancel != null) {
      throw ArgumentError('cancel and cancellation cannot be used together');
    }
    if (cancellation == null) {
      return null;
    }
    if (cancellation.isCancelled) {
      throw CoreCancelledError(cause: _cancellationReason(cancellation));
    }

    final dioCancel = CancelToken();
    void onCancel() => dioCancel.cancel();
    // Each request owns its listener and removes it when the request ends.
    cancellation.addListener(onCancel);
    return _CancellationBinding(cancellation, onCancel, dioCancel);
  }

  /// Get请求，返回String
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<String> getText(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
    CoreCancellation? cancellation,
    Duration? timeout,
  }) async {
    final binding = _bindCancellation(cancellation, cancel);
    final requestCancel =
        binding?.dioToken ?? cancel ?? (timeout == null ? null : CancelToken());
    var timedOut = false;
    final timeoutTimer = timeout == null
        ? null
        : Timer(timeout, () {
            timedOut = true;
            requestCancel?.cancel('hard timeout');
          });
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.plain,
          headers: header,
        ),
        cancelToken: requestCancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        if (timedOut) {
          throw CoreError(
            "发送GET请求超时",
            kind: CoreErrorKind.network,
            cause: e,
          );
        }
        throw CoreCancelledError(cause: e);
      } else if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "",
            statusCode: e.response?.statusCode ?? 0,
            kind: CoreErrorKind.http,
            cause: e);
      } else {
        throw CoreError("发送GET请求失败", kind: CoreErrorKind.network, cause: e);
      }
    } finally {
      timeoutTimer?.cancel();
      binding?.dispose();
    }
  }

  /// Get请求，返回原始二进制数据。
  ///
  /// 用于 protobuf、压缩包等不能经过文本解码的响应。
  Future<List<int>> getBytes(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
    CoreCancellation? cancellation,
    Duration? timeout,
  }) async {
    final binding = _bindCancellation(cancellation, cancel);
    final requestCancel =
        binding?.dioToken ?? cancel ?? (timeout == null ? null : CancelToken());
    var timedOut = false;
    final timeoutTimer = timeout == null
        ? null
        : Timer(timeout, () {
            timedOut = true;
            requestCancel?.cancel('hard timeout');
          });
    try {
      queryParameters ??= {};
      header ??= {};
      final result = await dio.get<List<int>>(
        url,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.bytes, headers: header),
        cancelToken: requestCancel,
      );
      return result.data ?? const <int>[];
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        if (timedOut) {
          throw CoreError(
            "发送GET二进制请求超时",
            kind: CoreErrorKind.network,
            cause: e,
          );
        }
        throw CoreCancelledError(cause: e);
      } else if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(
          e.message ?? "",
          statusCode: e.response?.statusCode ?? 0,
          kind: CoreErrorKind.http,
          cause: e,
        );
      } else {
        throw CoreError("发送GET二进制请求失败", kind: CoreErrorKind.network, cause: e);
      }
    } finally {
      timeoutTimer?.cancel();
      binding?.dispose();
    }
  }

  /// Get请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
    CoreCancellation? cancellation,
    Duration? timeout,
  }) async {
    final binding = _bindCancellation(cancellation, cancel);
    final requestCancel =
        binding?.dioToken ?? cancel ?? (timeout == null ? null : CancelToken());
    var timedOut = false;
    final timeoutTimer = timeout == null
        ? null
        : Timer(timeout, () {
            timedOut = true;
            requestCancel?.cancel('hard timeout');
          });
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
        ),
        cancelToken: requestCancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        if (timedOut) {
          throw CoreError(
            "发送GET请求超时",
            kind: CoreErrorKind.network,
            cause: e,
          );
        }
        throw CoreCancelledError(cause: e);
      } else if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "",
            statusCode: e.response?.statusCode ?? 0,
            kind: CoreErrorKind.http,
            cause: e);
      } else {
        throw CoreError("发送GET请求失败", kind: CoreErrorKind.network, cause: e);
      }
    } finally {
      timeoutTimer?.cancel();
      binding?.dispose();
    }
  }

  /// Post请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [data] 内容
  /// * [cancel] 任务取消Token
  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    bool formUrlEncoded = false,
    CancelToken? cancel,
    CoreCancellation? cancellation,
  }) async {
    final binding = _bindCancellation(cancellation, cancel);
    try {
      queryParameters ??= {};
      header ??= {};
      data ??= {};
      var result = await dio.post(
        url,
        queryParameters: queryParameters,
        data: data,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
          contentType:
              formUrlEncoded ? Headers.formUrlEncodedContentType : null,
        ),
        cancelToken: binding?.dioToken ?? cancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        throw CoreCancelledError(cause: e);
      } else if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "",
            statusCode: e.response?.statusCode ?? 0,
            kind: CoreErrorKind.http,
            cause: e);
      } else {
        throw CoreError("发送POST请求失败", kind: CoreErrorKind.network, cause: e);
      }
    } finally {
      binding?.dispose();
    }
  }

  /// Head请求，返回Response
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response> head(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
    CoreCancellation? cancellation,
  }) async {
    final binding = _bindCancellation(cancellation, cancel);
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.head(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: header,
          receiveDataWhenStatusError: true,
        ),
        cancelToken: binding?.dioToken ?? cancel,
      );
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        throw CoreCancelledError(cause: e);
      } else if (e is DioException && e.type == DioExceptionType.badResponse) {
        //throw CoreError(e.message, statusCode: e.response?.statusCode ?? 0);
        return e.response!;
      } else {
        throw CoreError("发送HEAD请求失败", kind: CoreErrorKind.network, cause: e);
      }
    } finally {
      binding?.dispose();
    }
  }
}

class _CancellationBinding {
  final CoreCancellation cancellation;
  final void Function() listener;
  final CancelToken dioToken;

  _CancellationBinding(this.cancellation, this.listener, this.dioToken);

  void dispose() => cancellation.removeListener(listener);
}

Object? _cancellationReason(CoreCancellation cancellation) {
  return cancellation is CoreCancellationToken ? cancellation.reason : null;
}
