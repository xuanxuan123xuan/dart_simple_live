import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/kuaishou/web_login_controller.dart';

void main() {
  test('constructing the controller does not eagerly require a WebView plugin',
      () {
    expect(() => KuaishouWebLoginController(), returnsNormally);
  });

  group('hasKuaishouAuthenticatedSession', () {
    test('does not treat the anonymous kwfv1 cookie as a login', () {
      expect(
        hasKuaishouAuthenticatedSession(
          'did=web_anonymous; kwfv1=guest-signature; kwssectoken=token',
        ),
        isFalse,
      );
    });

    test('accepts Kuaishou live authentication cookies', () {
      expect(
        hasKuaishouAuthenticatedSession(
          'did=web_user; kuaishou.live.web_st=authenticated-token',
        ),
        isTrue,
      );
    });

    test('rejects an empty authentication cookie', () {
      expect(
        hasKuaishouAuthenticatedSession('kuaishou.live.web_st=; kwfv1=x'),
        isFalse,
      );
    });
  });

  group('resolveKuaishouAuthCookieExpiry', () {
    test('uses the primary session cookie instead of the latest companion', () {
      final primary = DateTime(2026, 7, 20).millisecondsSinceEpoch;
      final companion = DateTime(2026, 8, 20).millisecondsSinceEpoch;

      expect(
        resolveKuaishouAuthCookieExpiry({
          'kuaishou.live.web_st': [primary],
          'passToken': [companion],
        })?.millisecondsSinceEpoch,
        primary,
      );
    });

    test('uses the earliest copy of the same auth cookie across domains', () {
      final earlier = DateTime(2026, 7, 18).millisecondsSinceEpoch;
      final later = DateTime(2026, 7, 19).millisecondsSinceEpoch;

      expect(
        resolveKuaishouAuthCookieExpiry({
          'kuaishou.live.web_st': [later, earlier],
        })?.millisecondsSinceEpoch,
        earlier,
      );
    });

    test('returns null when the browser exposes no expiry attributes', () {
      expect(resolveKuaishouAuthCookieExpiry(const {}), isNull);
    });
  });
}
