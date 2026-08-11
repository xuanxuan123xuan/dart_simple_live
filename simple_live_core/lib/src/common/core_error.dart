enum CoreErrorKind { network, http, response, search, cancelled, unknown }

class CoreError extends Error {
  /// 错误码
  final int statusCode;

  /// 错误信息
  final String message;

  final CoreErrorKind kind;
  final Object? cause;

  CoreError(
    this.message, {
    this.statusCode = 0,
    this.kind = CoreErrorKind.unknown,
    this.cause,
  });
  @override
  String toString() {
    if (statusCode != 0) {
      return statusCodeToString(statusCode);
    }

    return message;
  }

  String statusCodeToString(int statusCode) {
    switch (statusCode) {
      case 400:
        return "错误的请求(400)";
      case 401:
        return "无权限访问资源(401)";
      case 403:
        return "无权限访问资源(403)";
      case 404:
        return "服务器找不到请求的资源(404)";
      case 444:
        return "抖音访问过于频繁或触发风控限制(444)，请稍后再试，避免连续刷新或重复进入直播间";
      case 429:
        return "请求过于频繁(429)，请稍后重试";
      case 500:
        return "服务器出现错误(500)";
      case 502:
        return "服务器出现错误(502)";
      case 503:
        return "服务器出现错误(503)";
      default:
        return "连接服务器失败，请稍后再试($statusCode)";
    }
  }
}

class CoreCancelledError extends CoreError {
  CoreCancelledError({Object? cause})
      : super(
          "请求已取消",
          kind: CoreErrorKind.cancelled,
          cause: cause,
        );

  @override
  String toString() => message;
}
