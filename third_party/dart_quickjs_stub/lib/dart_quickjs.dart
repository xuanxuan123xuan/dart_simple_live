/// 纯 Dart 测试替身：API 面与 third_party/dart_quickjs_compat 的
/// `JsRuntime` 保持一致（构造参数 / eval / dispose / isDisposed / JsException）。
///
/// core 的单测不执行 JS 签名（douyin_sign / douyu_sign 仅运行时使用），
/// 故此处 [JsRuntime.eval] 直接抛出 [UnsupportedError]，避免在
/// 无 Flutter / 无 C 工具链的纯 Dart 环境触发 native build hooks。
class JsException implements Exception {
  const JsException(this.message);

  final String message;

  @override
  String toString() => 'JsException: $message';
}

class JsRuntime {
  JsRuntime({int? memoryLimit, int? maxStackSize});

  bool _disposed = false;

  bool get isDisposed => _disposed;

  dynamic eval(String code, {String? filename, bool asModule = false}) {
    throw UnsupportedError(
      'JsRuntime stub：请勿在测试中执行 JS 签名（真实实现由 '
      'simple_live_app 的 dependency_overrides 提供 dart_quickjs_compat）。',
    );
  }

  void dispose() {
    _disposed = true;
  }
}
