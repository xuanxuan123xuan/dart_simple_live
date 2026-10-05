import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/douyin/web_login_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('constructing the controller does not eagerly require a WebView plugin',
      () {
    expect(() => DouyinWebLoginController(), returnsNormally);
  });

  test('uses the same search fingerprint on desktop and mobile WebViews', () {
    expect(
      DouyinWebLoginController().userAgent,
      DouyinSite.kSearchUserAgent,
    );
  });

  test('merges Cookie values from all Douyin WebView domains', () {
    final values = mergeDouyinCookieString(
      {'sessionid': 'old'},
      'ttwid=web; sessionid=new; msToken=token=with=equals',
    );

    expect(values, {
      'sessionid': 'new',
      'ttwid': 'web',
      'msToken': 'token=with=equals',
    });
  });

  group('normalizeDouyinJavascriptValue', () {
    test('unwraps JSON strings returned by InAppWebView', () {
      expect(normalizeDouyinJavascriptValue('"token"'), 'token');
    });

    test('keeps plain values and ignores null values', () {
      expect(normalizeDouyinJavascriptValue('plain-token'), 'plain-token');
      expect(normalizeDouyinJavascriptValue(null), isEmpty);
      expect(normalizeDouyinJavascriptValue('null'), isEmpty);
    });
  });

  group('hasDouyinAuthenticatedSession', () {
    test('accepts supported authenticated session cookies', () {
      expect(
        hasDouyinAuthenticatedSession('ttwid=anonymous; sessionid=credential'),
        isTrue,
      );
      expect(
        hasDouyinAuthenticatedSession('sid_guard=credential'),
        isTrue,
      );
      expect(
        hasDouyinAuthenticatedSession('sid_tt=credential'),
        isTrue,
      );
      expect(
        hasDouyinAuthenticatedSession('uid_tt=credential'),
        isTrue,
      );
      expect(
        hasDouyinAuthenticatedSession('login_status=1'),
        isTrue,
      );
    });

    test('rejects anonymous, similarly named, and empty cookies', () {
      expect(hasDouyinAuthenticatedSession('ttwid=anonymous'), isFalse);
      expect(
          hasDouyinAuthenticatedSession('not_sessionid=credential'), isFalse);
      expect(hasDouyinAuthenticatedSession('sessionid='), isFalse);
      expect(hasDouyinAuthenticatedSession('login_status=0'), isFalse);
    });

    test('parses names case-insensitively and preserves values with equals',
        () {
      expect(
        hasDouyinAuthenticatedSession('SESSIONID=part=two'),
        isTrue,
      );
    });
  });
}
