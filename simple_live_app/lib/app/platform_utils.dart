import 'dart:io';

class PlatformUtils {
  PlatformUtils._();

  static bool get isOhos => Platform.operatingSystem == 'ohos';

  static bool get isMobileApp => Platform.isAndroid || Platform.isIOS || isOhos;

  static bool get supportsInlineMultiRoom => !isMobileApp;
}
