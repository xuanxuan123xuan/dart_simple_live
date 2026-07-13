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
}
