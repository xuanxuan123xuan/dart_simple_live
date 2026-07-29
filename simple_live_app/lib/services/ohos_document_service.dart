import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:simple_live_app/app/utils.dart';

/// Native HarmonyOS document and system-share integration.
///
/// The generic share/file-picker packages used by the compatibility branch do
/// not register HarmonyOS implementations, so keep all platform calls behind
/// one small bridge instead of scattering clipboard fallbacks through the UI.
class OhosDocumentService {
  OhosDocumentService._();

  static const MethodChannel _channel =
      MethodChannel('simple_live/ohos_documents');

  static Future<void> shareText(
    String text, {
    String title = 'Simple Live',
    bool isUrl = false,
  }) async {
    if (!Utils.isOhos) {
      throw UnsupportedError(
          'HarmonyOS system share is only available on OHOS');
    }
    await _channel.invokeMethod<void>('shareText', {
      'text': text,
      'title': title,
      'isUrl': isUrl,
    });
  }

  static Future<void> shareFile(
    String path, {
    String title = 'Simple Live',
  }) async {
    if (!Utils.isOhos) {
      throw UnsupportedError('HarmonyOS file share is only available on OHOS');
    }
    await _channel.invokeMethod<void>('shareFile', {
      'path': path,
      'title': title,
    });
  }

  /// Opens the HarmonyOS document save picker and writes [bytes] to the URI
  /// selected by the user. Returns false when the picker is cancelled.
  static Future<bool> saveBytes({
    required String fileName,
    required Uint8List bytes,
    String? extension,
  }) async {
    if (!Utils.isOhos) {
      throw UnsupportedError(
          'HarmonyOS document save is only available on OHOS');
    }
    final uri = await _channel.invokeMethod<String>('saveBytes', {
      'fileName': fileName,
      'extension': extension ?? _extensionOf(fileName),
      'bytes': bytes,
    });
    return uri != null && uri.isNotEmpty;
  }

  static Future<bool> saveText({
    required String fileName,
    required String content,
    String? extension,
  }) {
    return saveBytes(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      extension: extension,
    );
  }

  static String _extensionOf(String fileName) {
    final index = fileName.lastIndexOf('.');
    return index < 0 ? '' : fileName.substring(index + 1);
  }
}
