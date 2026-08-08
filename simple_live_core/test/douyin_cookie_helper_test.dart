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
}
