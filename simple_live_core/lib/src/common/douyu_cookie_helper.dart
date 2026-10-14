import 'dart:convert';
import 'dart:io';

/// Cookie parsing shared by the account UI and the playback session.
/// JWT expiry describes the local token lifetime, not server-side validity.
class DouyuCookieHelper {
  const DouyuCookieHelper._();

  static final _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  static String normalizeInput(String input) => _serialize(parse(input));

  static Map<String, String> parse(String input) {
    final header = RegExp(
      r'(?:^|\r?\n)\s*cookie\s*:\s*([^\r\n]*)',
      caseSensitive: false,
    ).firstMatch(input);
    final value = header?.group(1) ?? input.trim();
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
