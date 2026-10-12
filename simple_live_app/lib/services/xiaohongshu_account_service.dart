import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'xiaohongshu_web_session_service.dart';

class XiaohongshuAccountService extends GetxService {
  static XiaohongshuAccountService get instance =>
      Get.find<XiaohongshuAccountService>();

  String cookie = '';
  final hasCookie = false.obs;

  @override
  void onInit() {
    cookie = normalizeCookie(LocalStorageService.instance
        .getValue(LocalStorageService.kXiaohongshuCookie, ''));
    hasCookie.value = cookie.isNotEmpty;
    _applyCookieToSite();
    super.onInit();
  }

  String normalizeCookie(String input) {
    final header = RegExp(
      r'(?:^|\r?\n)\s*cookie\s*:\s*([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(input);
    final value = header?.group(1) ?? input.trim();
    return XiaohongshuSite.normalizeCookie(value);
  }

  Future<bool> setCookie(String input) async {
    final normalized = normalizeCookie(input);
    if (input.trim().isNotEmpty && normalized.isEmpty) {
      return false;
    }

    await LocalStorageService.instance.setValue(
      LocalStorageService.kXiaohongshuCookie,
      normalized,
    );
    final previousCookie = cookie;
    cookie = normalized;
    hasCookie.value = cookie.isNotEmpty;
    _applyCookieToSite();
    if (Get.isRegistered<XiaohongshuWebSessionService>()) {
      await XiaohongshuWebSessionService.instance.cookieChanged(previousCookie);
    }
    return true;
  }

  Future<void> clearCookie() async {
    await setCookie('');
  }

  void _applyCookieToSite() {
    final site =
        Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;
    site.cookie = cookie;
  }
}
