class DouyinCookieHelper {
  static bool hasCustomCookie(String cookie) {
    return cookie.trim().isNotEmpty;
  }

  static bool isOnlyTtwid(String cookie) {
    final cookies = _parseCookieMap(cookie);
    return cookies.length == 1 && cookies.containsKey("ttwid");
  }

  static bool hasFullCookie(String cookie) {
    return hasLoginSession(cookie);
  }

  static bool hasLoginSession(String cookie) {
    final cookies = _parseCookieMap(cookie);
    for (final name in const ["sessionid", "sid_guard", "sid_tt", "uid_tt"]) {
      if (cookies[name]?.isNotEmpty ?? false) {
        return true;
      }
    }
    return cookies["login_status"] == "1";
  }

  static DateTime? parseExpiry(String cookie) {
    final sidGuard = _parseCookieMap(cookie)["sid_guard"];
    if (sidGuard == null || sidGuard.isEmpty) {
      return null;
    }

    String decoded;
    try {
      decoded = Uri.decodeQueryComponent(sidGuard);
    } catch (_) {
      try {
        decoded = Uri.decodeComponent(sidGuard);
      } catch (_) {
        decoded = sidGuard;
      }
    }
    final parts = decoded.split("|");
    if (parts.length >= 3) {
      final loginTime = int.tryParse(parts[1]);
      final maxAgeSeconds = int.tryParse(parts[2]);
      if (loginTime != null && maxAgeSeconds != null) {
        try {
          final loginAt = loginTime > 1000000000000
              ? DateTime.fromMillisecondsSinceEpoch(loginTime, isUtc: true)
              : DateTime.fromMillisecondsSinceEpoch(
                  loginTime * 1000,
                  isUtc: true,
                );
          return loginAt.add(Duration(seconds: maxAgeSeconds)).toLocal();
        } on ArgumentError {
          // Fall through to the explicit expiry date, if present.
        }
      }
    }
    if (parts.length >= 4) {
      return _tryParseCookieDate(parts[3]);
    }
    return null;
  }

  static String cookieCompletenessHint(String cookie) {
    final normalized = cookie.trim();
    if (normalized.isEmpty) {
      return "未配置 Cookie";
    }
    if (isOnlyTtwid(normalized)) {
      return "仅检测到 ttwid，播放通常可用，但抖音关注状态可能需要完整 Cookie";
    }
    if (hasLoginSession(normalized)) {
      return "已检测到完整登录 Cookie；若仍失败，可能是 Cookie 过期或抖音风控";
    }
    return "已保存自定义 Cookie，但未识别到典型登录字段；若刷新失败，建议重新从浏览器复制完整 Request Headers";
  }

  static String normalizeInput(String input) {
    var cookie = extractCookieFromHeaderText(input) ?? input.trim();
    if (cookie.toLowerCase().startsWith("cookie:")) {
      cookie = cookie.substring(cookie.indexOf(":") + 1).trim();
    }
    if (!cookie.contains("=")) {
      cookie = 'ttwid=$cookie';
    }
    return cookie;
  }

  static String? extractCookieFromHeaderText(String input) {
    final lines = input
        .split(RegExp(r"\r?\n"))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (lower.startsWith("cookie:")) {
        return line.substring(line.indexOf(":") + 1).trim();
      }
      if (lower == "cookie" && i + 1 < lines.length) {
        return lines[i + 1].trim();
      }
    }
    return null;
  }

  static Map<String, String> _parseCookieMap(String input) {
    final cookie = (extractCookieFromHeaderText(input) ?? input).trim();
    final result = <String, String>{};
    for (final part in cookie.split(";")) {
      final item = part.trim();
      final separator = item.indexOf("=");
      if (separator <= 0) {
        continue;
      }
      final name = item.substring(0, separator).trim().toLowerCase();
      final value = item.substring(separator + 1).trim();
      if (name.isNotEmpty) {
        result[name] = value;
      }
    }
    return result;
  }

  static DateTime? _tryParseCookieDate(String value) {
    final normalized = value.replaceAll("+", " ").replaceAll("-", " ");
    final isoDate = DateTime.tryParse(normalized);
    if (isoDate != null) {
      return isoDate.toLocal();
    }
    final match = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{2}):(\d{2}):(\d{2})\s+(?:GMT|UTC)$',
      caseSensitive: false,
    ).firstMatch(normalized.trim());
    if (match == null) {
      return null;
    }
    const months = {
      "jan": 1,
      "feb": 2,
      "mar": 3,
      "apr": 4,
      "may": 5,
      "jun": 6,
      "jul": 7,
      "aug": 8,
      "sep": 9,
      "oct": 10,
      "nov": 11,
      "dec": 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) {
      return null;
    }
    try {
      return DateTime.utc(
        int.parse(match.group(3)!),
        month,
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      ).toLocal();
    } on ArgumentError {
      return null;
    }
  }
}
