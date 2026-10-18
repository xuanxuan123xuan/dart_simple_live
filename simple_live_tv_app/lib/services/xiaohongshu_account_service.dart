import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'xiaohongshu_web_session_service.dart';

class XiaohongshuAccountService extends GetxService {
  XiaohongshuAccountService(
      {LocalStorageService? storage, XiaohongshuSite? site})
      : _storageOverride = storage,
        _siteOverride = site;
  final LocalStorageService? _storageOverride;
  final XiaohongshuSite? _siteOverride;
  LocalStorageService get _storage =>
      _storageOverride ?? LocalStorageService.instance;
  XiaohongshuSite get _site =>
      _siteOverride ??
      Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;
  Future<void> _pendingWrite = Future<void>.value();
  static XiaohongshuAccountService get instance =>
      Get.find<XiaohongshuAccountService>();

  String cookie = '';
  final hasCookie = false.obs;
  final cookieRevision = 0.obs;

  @override
  void onInit() {
    cookie = normalizeCookie(
        _storage.getValue(LocalStorageService.kXiaohongshuCookie, ''));
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

    final write = _pendingWrite.then((_) async {
      await _storage.setValue(
          LocalStorageService.kXiaohongshuCookie, normalized);
      final previousCookie = cookie;
      cookie = normalized;
      hasCookie.value = cookie.isNotEmpty;
      _applyCookieToSite();
      if (Get.isRegistered<XiaohongshuWebSessionService>()) {
        await XiaohongshuWebSessionService.instance
            .cookieChanged(previousCookie);
      }
      cookieRevision.value++;
    });
    _pendingWrite = write.catchError((Object _) {});
    await write;
    return true;
  }

  Future<void> clearCookie() async {
    await setCookie('');
  }

  void _applyCookieToSite() {
    _site.cookie = cookie;
  }
}
