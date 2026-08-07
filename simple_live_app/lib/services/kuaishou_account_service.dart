import 'dart:convert';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class KuaishouAccountService extends GetxService {
  static KuaishouAccountService get instance =>
      Get.find<KuaishouAccountService>();
  var cookie = "";
  var kww = "";
  var hasCookie = false.obs;
  var cookieExpiresAtMs = 0.obs;

  DateTime? get cookieExpiresAt => cookieExpiresAtMs.value > 0
      ? DateTime.fromMillisecondsSinceEpoch(cookieExpiresAtMs.value)
      : null;
  @override
  void onInit() {
    cookie = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouCookie,
      "",
    );
    kww = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouKww,
      "",
    );
    cookieExpiresAtMs.value = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouCookieExpiresAt,
      0,
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    final site = Sites.allSites[Constant.kKuaishou]?.liveSite;
    if (site is KuaishouSite) {
      site.customCookie = cookie;
      site.customKww = kww;
      // 账号切换 / Cookie 变化：显式清空长期会话与共享 Cookie 字段，
      // 避免旧账号 Cookie 污染新账号。
      site.resetCookieSession();
    }
  }

  void setCookie(String cookie, {String? kww, DateTime? expiresAt}) {
    this.cookie = cookie;
    if (kww != null) {
      this.kww = kww;
    }
    LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouCookie,
      cookie,
    );
    LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouKww,
      this.kww,
    );
    final resolvedExpiry =
        expiresAt ?? resolveKuaishouEmbeddedTokenExpiry(cookie);
    cookieExpiresAtMs.value = resolvedExpiry?.millisecondsSinceEpoch ?? 0;
    LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouCookieExpiresAt,
      cookieExpiresAtMs.value,
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    kww = "";
    LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouCookie,
      "",
    );
    LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouKww,
      "",
    );
    cookieExpiresAtMs.value = 0;
    LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouCookieExpiresAt,
      0,
    );
    hasCookie.value = false;
    setSite();
  }
}

/// Returns an exact expiry only when an authentication cookie embeds a
/// standard JWT-style `exp` value. Opaque Kuaishou tokens deliberately return
/// null rather than inventing a lifetime that the server did not expose.
DateTime? resolveKuaishouEmbeddedTokenExpiry(String cookie) {
  final values = <String, String>{};
  for (final part in cookie.split(';')) {
    final item = part.trim();
    final index = item.indexOf('=');
    if (index <= 0) {
      continue;
    }
    values[item.substring(0, index).trim()] = item.substring(index + 1).trim();
  }
  for (final name in const [
    'kuaishou.live.web_st',
    'kuaishou.server.web_st',
    'kuaishou.live.web_at',
    'passToken',
  ]) {
    final expiry = _decodeTokenExpiry(values[name] ?? '');
    if (expiry != null) {
      return expiry;
    }
  }
  return null;
}

DateTime? _decodeTokenExpiry(String rawToken) {
  if (rawToken.isEmpty) {
    return null;
  }
  String token;
  try {
    token = Uri.decodeComponent(rawToken);
  } catch (_) {
    token = rawToken;
  }
  final parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (payload is! Map) {
      return null;
    }
    final rawExpiry = payload['exp'] ??
        payload['expiresAt'] ??
        payload['expireAt'] ??
        payload['expiration'];
    final numericExpiry = rawExpiry is num
        ? rawExpiry.toInt()
        : int.tryParse(rawExpiry?.toString() ?? '');
    if (numericExpiry == null || numericExpiry <= 0) {
      return null;
    }
    final milliseconds =
        numericExpiry < 100000000000 ? numericExpiry * 1000 : numericExpiry;
    final expiry = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    // Reject nonsensical payload values instead of surfacing a bogus date.
    if (expiry.year < 2020 || expiry.year > 2200) {
      return null;
    }
    return expiry;
  } catch (_) {
    return null;
  }
}
