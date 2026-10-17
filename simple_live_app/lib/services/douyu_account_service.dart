import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuCookieSaveException implements Exception {
  const DouyuCookieSaveException(this.cause, {this.rollbackRevision});

  final Object cause;

  /// The user revision restored by this write, only when it owned the rollback.
  final int? rollbackRevision;

  @override
  String toString() => 'DouyuCookieSaveException: Cookie persistence failed';
}

class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  String _cookie = '';
  String get cookie => _cookie;
  int get userCookieRevision => _userCookieGeneration;
  int _userCookieGeneration = 0;
  final hasCookie = false.obs;
  final cookieRevision = 0.obs;
  Future<void> _pendingWrite = Future<void>.value();
  bool _closed = false;

  DouyuSite get _site => Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;

  @override
  void onInit() {
    _cookie = DouyuCookieHelper.normalizeInput(LocalStorageService.instance
        .getValue(LocalStorageService.kDouyuCookie, ''));
    hasCookie.value = _cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    _site.cookie = _cookie;
    _site.onCookieRefreshed = _persistRefreshedCookie;
  }

  Future<bool> setCookie(String input) async {
    final normalized = DouyuCookieHelper.normalizeInput(input);
    if (input.trim().isNotEmpty && normalized.isEmpty) return false;
    // Apply the user's intent before the disk write, invalidating any
    // playback/refresh request that still owns the previous credentials.
    final previous = _cookie;
    _userCookieGeneration++;
    _acceptCookie(normalized);
    _site.cookie = normalized;
    final revision = cookieRevision.value;
    try {
      await _persistCookie(normalized);
    } catch (error, stackTrace) {
      int? rollbackRevision;
      if (!_closed && cookieRevision.value == revision) {
        _userCookieGeneration++;
        _acceptCookie(previous);
        _site.cookie = previous;
        rollbackRevision = userCookieRevision;
      }
      Error.throwWithStackTrace(
        DouyuCookieSaveException(error, rollbackRevision: rollbackRevision),
        stackTrace,
      );
    }
    return true;
  }

  Future<void> clearCookie() async {
    await setCookie('');
  }

  String get summary {
    cookieRevision.value;
    if (_cookie.isEmpty) return '未配置 Cookie（可选）';
    final fields = DouyuCookieHelper.parse(_cookie);
    final canRefresh = (fields['LTP0'] ?? '').isNotEmpty &&
        ((fields['dy_did'] ?? fields['acf_did'] ?? '').isNotEmpty);
    final expires = DouyuCookieHelper.jwtExpiresAt(_cookie);
    if (expires == null) return '已配置 Cookie，登录状态待确认';
    if (!expires.isAfter(DateTime.now())) {
      return canRefresh ? 'Cookie 已过期，播放时尝试自动续期' : 'Cookie 已过期，请重新粘贴';
    }
    return canRefresh ? '已配置 Cookie，可自动续期' : '已配置 Cookie';
  }

  void _acceptCookie(String value) {
    _cookie = value;
    hasCookie.value = value.isNotEmpty;
    cookieRevision.value++;
  }

  Future<void> _persistRefreshedCookie(String value) {
    if (_closed || _site.cookie != value) return Future<void>.value();
    // Core has already advanced its session before invoking this callback.
    // Do not set site.cookie again and invalidate that newly accepted session.
    _acceptCookie(value);
    return _persistCookie(value);
  }

  Future<void> _persistCookie(String value) {
    final write = _pendingWrite.then((_) async {
      await LocalStorageService.instance.setValue(
        LocalStorageService.kDouyuCookie,
        value,
      );
    });
    // Preserve write ordering while allowing later user changes after a
    // failed write. The caller still observes this write's failure.
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  @override
  void onClose() {
    _closed = true;
    if (_site.onCookieRefreshed == _persistRefreshedCookie) {
      _site.onCookieRefreshed = null;
    }
    super.onClose();
  }
}
