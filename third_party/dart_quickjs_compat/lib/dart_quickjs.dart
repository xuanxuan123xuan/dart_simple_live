import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/js_eval_result.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

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
///
/// On iOS and macOS, QuickJS FFI is not available (no native C library
/// compiled), so we use JavaScriptCore instead — the system JavaScript
/// engine that flutter_js already binds to natively on those platforms.
class JsRuntime {
  JsRuntime({int? memoryLimit, int? maxStackSize})
      : _isJSCore = Platform.isIOS || Platform.isMacOS,
        _runtime = (Platform.isIOS || Platform.isMacOS)
            ? JavascriptCoreRuntime()
            : QuickJsRuntime2(
                stackSize: maxStackSize ?? 512 * 1024,
                memoryLimit: memoryLimit,
              );

  final JavascriptRuntime _runtime;
  final bool _isJSCore;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  dynamic eval(String code, {String? filename, bool asModule = false}) {
    if (_disposed) {
      throw const JsException('Runtime has been disposed');
    }

    final JsEvalResult result;
    if (_isJSCore) {
      result = (_runtime as JavascriptCoreRuntime)
          .evaluate(code, sourceUrl: filename);
    } else {
      result = (_runtime as QuickJsRuntime2)
          .evaluate(code, name: filename);
    }

    if (result.isError) {
      throw JsException(result.stringResult);
    }

    // QuickJsRuntime2 converts JS values to native Dart types via _jsToDart(),
    // so rawResult is already a Dart String/int/List/etc.
    // JavascriptCoreRuntime stores the raw JSValueRef pointer in rawResult;
    // use stringResult which is the toString'd JS value (via jSValueToStringCopy).
    if (_isJSCore) {
      return result.stringResult;
    }
    return result.rawResult;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime.dispose();
  }
}
