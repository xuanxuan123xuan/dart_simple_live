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

/// 快手返回了需要用户在网页中完成的滑块验证。
///
/// 这是可恢复的会话状态，不应被当作普通 403、限流或凭据失效处理；
/// 调用方可以用 [roomId] 和 [sessionKey] 在应用内打开对应网页并恢复会话。
class KuaishouVerificationRequiredError extends CoreError {
  KuaishouVerificationRequiredError({
    required this.roomId,
    this.sessionKey,
    Object? cause,
  }) : super(
          '请在快手页面完成滑块验证或安全验证后重试',
          statusCode: 403,
          kind: CoreErrorKind.http,
          cause: cause,
        );

  final String roomId;
  final String? sessionKey;

  @override
  String toString() => message;
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
