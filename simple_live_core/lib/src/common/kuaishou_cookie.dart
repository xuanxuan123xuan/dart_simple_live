const Set<String> _kuaishouDeviceCookieNames = {
  'did',
  'didv',
  'clientid',
  'client_key',
  'kpn',
  'kuaishou.live.bfb1s',
};

/// Removes device-scoped fields from a portable Kuaishou credential cookie.
/// Authentication tokens, UID fields, kwfv1 and unknown fields are preserved.
String sanitizeKuaishouCredentialCookie(String cookie) {
  return cookie.split(';').map((item) => item.trim()).where((item) {
    if (item.isEmpty) return false;
    final separator = item.indexOf('=');
    if (separator <= 0) return true;
    final name = item.substring(0, separator).trim().toLowerCase();
    return !_kuaishouDeviceCookieNames.contains(name);
  }).join('; ');
}
