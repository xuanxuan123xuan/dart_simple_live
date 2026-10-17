import 'dart:convert';
import 'dart:io';

/// Cookie parsing shared by the account UI and the playback session.
/// JWT expiry describes the local token lifetime, not server-side validity.
class DouyuCookieHelper {
  const DouyuCookieHelper._();

  static final _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  static String normalizeInput(String input) => _serialize(parse(input));

  /// Combines cookies read from Douyu's root, passport, and www domains.
  /// www cookies win for duplicate fields; passport is preferred for LTP0,
  /// whose domain is commonly scoped to the login host.
  static String mergeBrowserCookies({
    required String rootCookie,
    required String passportCookie,
    required String wwwCookie,
  }) {
    final root = _nonEmpty(parse(rootCookie));
    final passport = _nonEmpty(parse(passportCookie));
    final www = _nonEmpty(parse(wwwCookie));
    final values = <String, String>{...root, ...passport, ...www};

    final ltp0 = passport['LTP0'] ?? www['LTP0'] ?? root['LTP0'];
    if (ltp0 != null) {
      values['LTP0'] = ltp0;
    }

    // Douyu may expose both names in a browser jar. Prefer the www device ID
    // for duplicate names, while preserving both fields when they are present.
    final dyDid = www['dy_did'] ?? root['dy_did'] ?? passport['dy_did'];
    if (dyDid != null) {
      values['dy_did'] = dyDid;
    }

    return _serialize(values);
  }

  /// True when the browser session has the credential pair used for refresh.
  static bool hasRefreshCredentials(String cookie) {
    final fields = parse(cookie);
    final ltp0 = fields['LTP0']?.trim() ?? '';
    final deviceId = fields['dy_did']?.trim().isNotEmpty == true ||
        fields['acf_did']?.trim().isNotEmpty == true;
    return ltp0.isNotEmpty && deviceId;
  }

  /// Checks local login evidence without treating anonymous/device cookies as
  /// authentication. JWT expiry is a local hint; the server remains the
  /// authority for whether the token is accepted.
  static bool hasAuthenticatedSession(String cookie, {DateTime? now}) {
    final fields = parse(cookie);
    final currentTime = now ?? DateTime.now();
    final expiresAt = jwtExpiresAt(cookie);
    if (expiresAt != null && expiresAt.isAfter(currentTime)) {
      return true;
    }

    final auth = fields['acf_auth']?.trim() ?? '';
    final uid = fields['acf_uid']?.trim() ?? '';
    final numericUid = int.tryParse(uid);
    return auth.isNotEmpty && numericUid != null && numericUid > 0;
  }

  static Map<String, String> _nonEmpty(Map<String, String> fields) => {
        for (final entry in fields.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value,
      };

  static Map<String, String> parse(String input) {
    final headerPattern = RegExp(
      r'(?:^|\r?\n)\s*cookie\s*:\s*([^\r\n]*)',
      caseSensitive: false,
    );
    final headers =
        headerPattern.allMatches(input).map((match) => match.group(1)!);
    final value = headers.isEmpty ? input.trim() : headers.join('; ');
    final pairs = <String, String>{};
    for (final part in value.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      final cookieValue = part.substring(separator + 1).trim();
      if (!_cookieName.hasMatch(name) ||
          cookieValue.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        continue;
      }
      pairs[name] = cookieValue;
    }
    return pairs;
  }

  static DateTime? jwtExpiresAt(String cookie) {
    final token = parse(cookie)['acf_jwt_token'];
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(parts[1]),
      )));
      final expiry = payload is Map ? payload['exp'] : null;
      if (expiry is! int || expiry <= 0 || expiry > 8640000000000) return null;
      return DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static bool needsRefresh(String cookie, DateTime now) {
    if (normalizeInput(cookie).isEmpty) return false;
    final expiry = jwtExpiresAt(cookie);
    return expiry == null || !expiry.isAfter(now);
  }

  /// Each element is one Set-Cookie header. Expires contains commas, so a
  /// combined string must never be split on commas.
  static String mergeSetCookie(
    String original,
    List<String> headers,
    DateTime now,
  ) {
    final pairs = parse(original);
    for (final header in headers) {
      try {
        final updated = Cookie.fromSetCookieValue(header);
        if (!_cookieName.hasMatch(updated.name) ||
            updated.value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
          continue;
        }
        // Max-Age takes precedence over Expires, including deletion.
        final maxAge = updated.maxAge;
        final deleted = maxAge != null
            ? maxAge <= 0
            : updated.expires != null && !updated.expires!.isAfter(now);
        if (deleted) {
          pairs.remove(updated.name);
        } else {
          pairs[updated.name] = updated.value;
        }
      } on HttpException {
        // dart:io rejects malformed Set-Cookie syntax with HttpException.
      } on FormatException {
        // A malformed field cannot invalidate the other refresh cookies.
      }
    }
    return _serialize(pairs);
  }

  static String _serialize(Map<String, String> pairs) =>
      pairs.entries.map((pair) => '${pair.key}=${pair.value}').join('; ');
}
