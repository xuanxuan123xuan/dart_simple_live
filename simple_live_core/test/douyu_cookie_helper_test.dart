import 'dart:convert';

import 'package:simple_live_core/src/common/douyu_cookie_helper.dart';
import 'package:test/test.dart';

String _jwt(Object expiry) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
              'exp': expiry
            }))).replaceAll('=', '')}.signature';

void main() {
  test('combines Cookie headers copied from multiple Douyu domains', () {
    final cookie = DouyuCookieHelper.normalizeInput(
      'Host: www.douyu.com\r\n'
      'Cookie: acf_auth=www-auth; acf_uid=42; dy_did=device\r\n'
      'Host: passport.douyu.com\r\n'
      'Cookie: LTP0=refresh; acf_auth=passport-auth',
    );

    expect(DouyuCookieHelper.parse(cookie), {
      'acf_auth': 'passport-auth',
      'acf_uid': '42',
      'dy_did': 'device',
      'LTP0': 'refresh',
    });
    expect(DouyuCookieHelper.hasRefreshCredentials(cookie), isTrue);
  });

  test('browser merge keeps login fields and both device ID names', () {
    final merged = DouyuCookieHelper.mergeBrowserCookies(
      rootCookie: 'dy_did=root-device; acf_did=root-acf-device',
      passportCookie: 'LTP0=passport-refresh; acf_auth=passport-auth',
      wwwCookie:
          'LTP0=www-refresh; acf_auth=www-auth; acf_uid=42; dy_did=www-device',
    );

    expect(DouyuCookieHelper.parse(merged), {
      'dy_did': 'www-device',
      'acf_did': 'root-acf-device',
      'LTP0': 'passport-refresh',
      'acf_auth': 'www-auth',
      'acf_uid': '42',
    });
    expect(DouyuCookieHelper.hasRefreshCredentials(merged), isTrue);
  });

  test('login evidence excludes anonymous and expired token cookies', () {
    final now = DateTime.utc(2026, 10, 14);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    expect(
      DouyuCookieHelper.hasAuthenticatedSession(
        'dy_did=device; LTP0=refresh',
        now: now,
      ),
      isFalse,
    );
    expect(
      DouyuCookieHelper.hasAuthenticatedSession(
        'acf_jwt_token=${_jwt(nowSeconds - 1)}',
        now: now,
      ),
      isFalse,
    );
    expect(
      DouyuCookieHelper.hasAuthenticatedSession(
        'acf_jwt_token=${_jwt(nowSeconds + 60)}',
        now: now,
      ),
      isTrue,
    );
    expect(
      DouyuCookieHelper.hasAuthenticatedSession(
        'acf_auth=auth; acf_uid=42',
        now: now,
      ),
      isTrue,
    );
    expect(
      DouyuCookieHelper.hasAuthenticatedSession(
        'acf_auth=auth; acf_uid=0',
        now: now,
      ),
      isFalse,
    );
  });

  test('refresh requires LTP0 and either device ID', () {
    expect(DouyuCookieHelper.hasRefreshCredentials('LTP0=refresh'), isFalse);
    expect(DouyuCookieHelper.hasRefreshCredentials('dy_did=device'), isFalse);
    expect(
      DouyuCookieHelper.hasRefreshCredentials('LTP0=refresh; acf_did=device'),
      isTrue,
    );
  });

  final now = DateTime.utc(2026, 10, 14);

  test('normalizes pasted headers and preserves equals and case in values', () {
    expect(
      DouyuCookieHelper.normalizeInput(
        'Host: www.douyu.com\r\nCookie: dy_did=device; LTP0=a=b=c; a=old; a=new',
      ),
      'dy_did=device; LTP0=a=b=c; a=new',
    );
    expect(DouyuCookieHelper.normalizeInput('COOKIE: a=1'), 'a=1');
    expect(DouyuCookieHelper.normalizeInput('a=1; invalid; =empty'), 'a=1');
    expect(DouyuCookieHelper.normalizeInput('invalid'), isEmpty);
    expect(DouyuCookieHelper.normalizeInput('a=1\r\nInjected: value'), isEmpty);
  });

  test('JWT expiry checks time without claiming authentication validity', () {
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final valid = 'acf_jwt_token=${_jwt(nowSeconds + 60)}';
    expect(DouyuCookieHelper.jwtExpiresAt(valid),
        now.add(const Duration(minutes: 1)));
    expect(DouyuCookieHelper.needsRefresh(valid, now), isFalse);
    expect(
        DouyuCookieHelper.needsRefresh(
            'acf_jwt_token=${_jwt(nowSeconds)}', now),
        isTrue);
    for (final token in ['broken', _jwt('later'), _jwt(-1), 'a.%%%.c']) {
      expect(DouyuCookieHelper.jwtExpiresAt('acf_jwt_token=$token'), isNull);
    }
    expect(DouyuCookieHelper.needsRefresh('acf_auth=legacy', now), isTrue);
    expect(DouyuCookieHelper.needsRefresh('', now), isFalse);
  });

  test('merges individual Set-Cookie headers without splitting Expires commas',
      () {
    final merged = DouyuCookieHelper.mergeSetCookie(
      'dy_did=device; LTP0=refresh; acf_auth=old; obsolete=1',
      [
        'acf_auth=new=value; Path=/; HttpOnly; Expires=Fri, 16 Oct 2026 00:00:00 GMT',
        'other=2; Path=/; Secure',
        'obsolete=deleted; Max-Age=0; Path=/',
        'invalid-header',
      ],
      now,
    );
    expect(DouyuCookieHelper.parse(merged), {
      'dy_did': 'device',
      'LTP0': 'refresh',
      'acf_auth': 'new=value',
      'other': '2',
    });
  });

  test('Max-Age overrides Expires and refresh-only fields can be rotated', () {
    final merged = DouyuCookieHelper.mergeSetCookie(
      'dy_did=device; LTP0=old; delete_by_date=1',
      [
        'LTP0=new; Max-Age=3600; Expires=Wed, 01 Jan 2020 00:00:00 GMT',
        'delete_by_date=gone; Expires=Wed, 01 Jan 2020 00:00:00 GMT',
      ],
      now,
    );
    expect(
        DouyuCookieHelper.parse(merged), {'dy_did': 'device', 'LTP0': 'new'});
  });
}
