import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('DouyinCookieHelper login session detection', () {
    test('recognizes the supported authenticated fields', () {
      for (final cookie in const [
        'sessionid=value',
        'SID_GUARD=value',
        ' sid_tt = value ',
        'uid_tt=value=with=equals',
        'login_status=1',
      ]) {
        expect(
          DouyinCookieHelper.hasLoginSession(cookie),
          isTrue,
          reason: cookie,
        );
        expect(DouyinCookieHelper.hasFullCookie(cookie), isTrue);
      }
    });

    test('rejects empty login values and non-authentication cookies', () {
      for (final cookie in const [
        '',
        'sessionid=',
        'login_status=0',
        'ttwid=value;',
        'ttwid=value; __ac_nonce=nonce',
      ]) {
        expect(
          DouyinCookieHelper.hasLoginSession(cookie),
          isFalse,
          reason: cookie,
        );
        expect(DouyinCookieHelper.hasFullCookie(cookie), isFalse);
      }
    });

    test('detects only ttwid despite casing, spacing, or trailing separators',
        () {
      expect(DouyinCookieHelper.isOnlyTtwid(' TTWID = value ; '), isTrue);
      expect(
        DouyinCookieHelper.isOnlyTtwid('ttwid=value; __ac_nonce=nonce'),
        isFalse,
      );
    });
  });

  group('DouyinCookieHelper expiry parsing', () {
    test('parses a percent-encoded sid_guard expiry', () {
      final expiry = DouyinCookieHelper.parseExpiry(
        'sessionid=value; sid_guard=hash%7C1700000000%7C3600',
      );

      expect(
        expiry?.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(
          1700003600 * 1000,
          isUtc: true,
        ),
      );
    });

    test('returns null for absent or malformed expiry metadata', () {
      expect(DouyinCookieHelper.parseExpiry('sessionid=value'), isNull);
      expect(DouyinCookieHelper.parseExpiry('sid_guard=malformed'), isNull);
      expect(
        DouyinCookieHelper.parseExpiry('sid_guard=hash%7Ctime%7Cduration'),
        isNull,
      );
      expect(
        () => DouyinCookieHelper.parseExpiry(
          'sid_guard=hash%7C999999999999999999999999999999%7C999999999999999999999999999999',
        ),
        returnsNormally,
      );
    });

    test('falls back to the explicit HTTP-date expiry', () {
      final expiry = DouyinCookieHelper.parseExpiry(
        'sid_guard=hash%7Cinvalid%7Cinvalid%7CWed%2C+15+Nov+2023+00%3A13%3A20+GMT',
      );

      expect(expiry?.toUtc(), DateTime.utc(2023, 11, 15, 0, 13, 20));
    });
  });

  group('DouyinCookieHelper input normalization', () {
    test('extracts a cookie from a JSON export', () {
      const input = '''{
  "cookie": "sessionid=user-session; ttwid=user-ttwid"
}''';

      expect(
        DouyinCookieHelper.normalizeInput(input),
        'sessionid=user-session; ttwid=user-ttwid',
      );
    });

    test('extracts a cookie from a double-encoded JSON export', () {
      const input = '"{\\"cookie\\":\\"sessionid=user-session\\"}"';

      expect(
        DouyinCookieHelper.normalizeInput(input),
        'sessionid=user-session',
      );
    });

    test('converts an exported browser cookie list', () {
      const input = '''[
  {"name": "sessionid", "value": "user-session"},
  {"name": "ttwid", "value": "user-ttwid"}
]''';

      expect(
        DouyinCookieHelper.normalizeInput(input),
        'sessionid=user-session; ttwid=user-ttwid',
      );
    });

    test('removes control characters from a header value', () {
      expect(
        DouyinCookieHelper.normalizeInput(
          'sessionid=user-session;\r\n ttwid=user-ttwid',
        ),
        'sessionid=user-session;  ttwid=user-ttwid',
      );
    });

    test('keeps an empty input empty', () {
      expect(DouyinCookieHelper.normalizeInput('  '), isEmpty);
    });
  });

  test('cookie completeness hint uses authenticated session semantics', () {
    expect(
      DouyinCookieHelper.cookieCompletenessHint(
        'ttwid=value; __ac_nonce=nonce',
      ),
      contains('未识别到典型登录字段'),
    );
    expect(
      DouyinCookieHelper.cookieCompletenessHint('sessionid=value'),
      contains('完整登录 Cookie'),
    );
  });

  group('DouyuCookieHelper authentication', () {
    test('requires LTP0 and a device ID to advertise refresh credentials', () {
      expect(
        DouyuCookieHelper.hasRefreshCredentials('LTP0=token; dy_did=device'),
        isTrue,
      );
      expect(
        DouyuCookieHelper.hasRefreshCredentials('LTP0=token; acf_did=device'),
        isTrue,
      );
      expect(DouyuCookieHelper.hasRefreshCredentials('LTP0=token'), isFalse);
      expect(DouyuCookieHelper.hasRefreshCredentials('dy_did=device'), isFalse);
      expect(
        DouyuCookieHelper.hasRefreshCredentials('LTP0=; acf_did=device'),
        isFalse,
      );
    });

    test('accepts future JWT or authenticated acf fields only', () {
      final token = _jwtWithExpiry(2000000000);
      expect(
        DouyuCookieHelper.hasAuthenticatedSession(
          'acf_jwt_token=$token',
          now: DateTime.utc(2030),
        ),
        isTrue,
      );
      expect(
        DouyuCookieHelper.hasAuthenticatedSession(
          'acf_jwt_token=${_jwtWithExpiry(1700000000)}',
          now: DateTime.utc(2030),
        ),
        isFalse,
      );
      expect(
        DouyuCookieHelper.hasAuthenticatedSession(
          'acf_auth=auth-token; acf_uid=42',
        ),
        isTrue,
      );
      for (final cookie in const [
        'ttwid=anonymous; dy_did=device',
        'LTP0=refresh-only; dy_did=device',
        'acf_auth=auth-token; acf_uid=0',
        'acf_auth=auth-token; acf_uid=not-a-number',
        'acf_auth=; acf_uid=42',
      ]) {
        expect(
          DouyuCookieHelper.hasAuthenticatedSession(cookie),
          isFalse,
          reason: cookie,
        );
      }
    });

    test('merges domain cookies with www auth and passport LTP0 precedence', () {
      final merged = DouyuCookieHelper.mergeBrowserCookies(
        rootCookie: 'acf_auth=root-auth; acf_uid=1; dy_did=root-device',
        passportCookie:
            'LTP0=passport-refresh; acf_auth=passport-auth; dy_did=passport-device',
        wwwCookie:
            'LTP0=www-refresh; acf_auth=www-auth; acf_uid=55; dy_did=www-device; acf_did=other-device; ttwid=browser-id',
      );
      final fields = DouyuCookieHelper.parse(merged);

      expect(fields['LTP0'], 'passport-refresh');
      expect(fields['acf_auth'], 'www-auth');
      expect(fields['acf_uid'], '55');
      expect(fields['dy_did'], 'www-device');
      expect(fields['acf_did'], 'other-device');
      expect(fields['ttwid'], 'browser-id');
    });
  });
}

String _jwtWithExpiry(int expiry) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': expiry})));
  return 'header.$payload.signature';
}
