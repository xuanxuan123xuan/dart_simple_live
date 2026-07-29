import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/douyin/web_login_controller.dart';

void main() {
  test('constructing the controller does not eagerly require a WebView plugin',
      () {
    expect(() => DouyinWebLoginController(), returnsNormally);
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
