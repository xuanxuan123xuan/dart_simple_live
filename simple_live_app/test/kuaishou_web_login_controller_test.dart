import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/kuaishou/web_login_controller.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';

void main() {
  test('constructing the controller does not eagerly require a WebView plugin',
      () {
    expect(() => KuaishouWebLoginController(), returnsNormally);
  });

  test('only the backup account requires a fresh browser session', () {
    expect(
      requiresFreshKuaishouLoginSession(KuaishouAccountSlot.primary),
      isFalse,
    );
    expect(
      requiresFreshKuaishouLoginSession(KuaishouAccountSlot.secondary),
      isTrue,
    );
  });

  group('KuaishouFreshLoginSessionCoordinator', () {
    test('clears cookies before enabling the first page bootstrap', () async {
      final coordinator = KuaishouFreshLoginSessionCoordinator();
      final events = <String>[];

      expect(coordinator.blocksAutoCheck, isTrue);
      await coordinator.prepare(clearCookies: () async {
        events.add('clear-cookies');
      });
      await coordinator.prepare(clearCookies: () async {
        events.add('unexpected-second-clear');
      });

      expect(events, ['clear-cookies']);
      expect(coordinator.prepared, isTrue);
      expect(coordinator.storageResetPending, isTrue);
      expect(coordinator.blocksAutoCheck, isTrue);
    });

    test('clears page state and cookies once before reloading', () async {
      final coordinator = KuaishouFreshLoginSessionCoordinator();
      final events = <String>[];
      await coordinator.prepare(clearCookies: () async {});

      Future<void> finish() => coordinator.finishBootstrap(
            clearPageStorage: () async {
              events.add('clear-storage');
            },
            clearCookies: () async {
              events.add('clear-cookies');
            },
            reload: () async {
              events.add('reload');
            },
          );

      await finish();
      await finish();

      expect(events, ['clear-storage', 'clear-cookies', 'reload']);
      expect(coordinator.storageResetPending, isFalse);
      expect(coordinator.blocksAutoCheck, isFalse);
    });

    test('failed preparation keeps automatic detection blocked', () async {
      final coordinator = KuaishouFreshLoginSessionCoordinator();

      await expectLater(
        coordinator.prepare(
          clearCookies: () async => throw StateError('clear failed'),
        ),
        throwsStateError,
      );

      expect(coordinator.prepared, isFalse);
      expect(coordinator.blocksAutoCheck, isTrue);
    });

    test('cleanup is idempotent and still attempts cookie removal', () async {
      final coordinator = KuaishouFreshLoginSessionCoordinator();
      var storageClearCount = 0;
      var cookieClearCount = 0;

      Future<void> cleanup() => coordinator.cleanup(
            clearPageStorage: () async {
              storageClearCount++;
            },
            clearCookies: () async {
              cookieClearCount++;
            },
          );

      await cleanup();
      await cleanup();

      expect(storageClearCount, 1);
      expect(cookieClearCount, 1);
      expect(coordinator.cleaned, isTrue);
      expect(coordinator.blocksAutoCheck, isTrue);
    });

    test('cleanup reports storage errors after clearing cookies', () async {
      final coordinator = KuaishouFreshLoginSessionCoordinator();
      var cookieClearCount = 0;

      await expectLater(
        coordinator.cleanup(
          clearPageStorage: () async => throw StateError('storage failed'),
          clearCookies: () async {
            cookieClearCount++;
          },
        ),
        throwsStateError,
      );

      expect(cookieClearCount, 1);
      expect(coordinator.cleaned, isFalse);
    });
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

  group('resolveKuaishouEmbeddedTokenExpiry', () {
    test('reads a seconds-based JWT exp from the primary auth cookie', () {
      const payload = 'eyJleHAiOjIwMDAwMDAwMDB9';
      final expiry = resolveKuaishouEmbeddedTokenExpiry(
        'did=x; kuaishou.live.web_st=header.$payload.signature',
      );

      expect(
        expiry,
        DateTime.fromMillisecondsSinceEpoch(2000000000 * 1000),
      );
    });

    test('does not invent an expiry for opaque cookies', () {
      expect(
        resolveKuaishouEmbeddedTokenExpiry(
          'kuaishou.live.web_st=opaque-token; passToken=also-opaque',
        ),
        isNull,
      );
    });

    test('uses auth-cookie priority when several JWT values exist', () {
      const primary = 'eyJleHAiOjIwMDAwMDAwMDB9';
      const companion = 'eyJleHAiOjIxMDAwMDAwMDB9';
      final expiry = resolveKuaishouEmbeddedTokenExpiry(
        'passToken=h.$companion.s; kuaishou.live.web_st=h.$primary.s',
      );

      expect(
        expiry,
        DateTime.fromMillisecondsSinceEpoch(2000000000 * 1000),
      );
    });
  });
}
