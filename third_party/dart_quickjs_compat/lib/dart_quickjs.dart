import 'package:flutter_js/quickjs/quickjs_runtime2.dart';

class JsException implements Exception {
  const JsException(this.message);

  final String message;

  @override
  String toString() => 'JsException: $message';
}

/// Compatibility facade for the API used by Simple Live 1.12.7.
///
/// The upstream package uses Dart 3.10 Native Assets, which the current
/// Flutter OHOS 3.22 toolchain cannot consume. This facade keeps its small
/// synchronous API while using the already ported QuickJS FFI bridge.
class JsRuntime {
  JsRuntime({int? memoryLimit, int? maxStackSize})
      : _runtime = QuickJsRuntime2(
          stackSize: maxStackSize ?? 512 * 1024,
        );

  final QuickJsRuntime2 _runtime;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  dynamic eval(String code, {String? filename, bool asModule = false}) {
    if (_disposed) {
      throw const JsException('Runtime has been disposed');
    }
    final result = _runtime.evaluate(code, name: filename);
    if (result.isError) {
      throw JsException(result.stringResult);
    }
    return result.rawResult;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime.dispose();
  }
}
