import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

void main() {
  test('account pool only degrades primary to secondary to anonymous', () {
    expect(
      degradeKuaishouMode(
        current: KuaishouAccountPoolMode.primary,
        secondaryAvailable: true,
      ),
      KuaishouAccountPoolMode.secondary,
    );
    expect(
      degradeKuaishouMode(
        current: KuaishouAccountPoolMode.secondary,
        secondaryAvailable: true,
      ),
      KuaishouAccountPoolMode.anonymous,
    );
    expect(
      degradeKuaishouMode(
        current: KuaishouAccountPoolMode.primary,
        secondaryAvailable: false,
      ),
      KuaishouAccountPoolMode.anonymous,
    );
  });

  test('invalid credential never becomes available at midnight', () {
    final session = KuaishouAccountSession(KuaishouAccountSlot.primary)
      ..cookie = 'kuaishou.live.web_st=token'
      ..credentialState = KuaishouCredentialState.invalid
      ..suspendedUntil = DateTime(2026, 1, 2);

    expect(session.isAvailable(DateTime(2026, 1, 3)), isFalse);
  });

  test('next Shanghai midnight covers month and year rollover', () {
    final monthEnd = nextShanghaiMidnight(DateTime.utc(2026, 11, 30, 15, 59));
    expect(monthEnd.toUtc(), DateTime.utc(2026, 11, 30, 16));

    final yearEnd = nextShanghaiMidnight(DateTime.utc(2026, 12, 31, 15));
    expect(yearEnd.toUtc(), DateTime.utc(2026, 12, 31, 16));
  });

  test('cookie comparison ignores ordering and whitespace', () {
    expect(
      normalizeKuaishouCookie('b=2; a=1'),
      normalizeKuaishouCookie(' a=1;b=2 '),
    );
  });

  test('account uid is only used when a reliable cookie field exists', () {
    expect(
      extractKuaishouAccountUid('foo=bar; userId=account_123; baz=qux'),
      'account_123',
    );
    expect(
      extractKuaishouAccountUid('kuaishou.live.web_st=opaque-token'),
      isNull,
    );
  });

  test('account session backup preserves credential and health state', () {
    final suspendedUntil = DateTime(2026, 8, 10);
    final source = KuaishouAccountSession(KuaishouAccountSlot.secondary)
      ..cookie = 'userId=backup_user; token=secondary'
      ..kww = 'secondary-kww'
      ..cookieExpiresAt = DateTime(2026, 9, 1)
      ..credentialState = KuaishouCredentialState.valid
      ..loggedInAt = DateTime(2026, 8, 1)
      ..lastValidatedAt = DateTime(2026, 8, 8)
      ..suspendedUntil = suspendedUntil
      ..suspendedReason = 'rateLimited';
    final restored = KuaishouAccountSession(KuaishouAccountSlot.secondary)
      ..restoreBackup(source.toBackupJson());

    expect(restored.cookie, source.cookie);
    expect(restored.kww, source.kww);
    expect(restored.cookieExpiresAt, source.cookieExpiresAt);
    expect(restored.credentialState, KuaishouCredentialState.valid);
    expect(restored.lastValidatedAt, source.lastValidatedAt);
    expect(restored.suspendedUntil, suspendedUntil);
    expect(restored.suspendedReason, 'rateLimited');
  });

  test('legacy single-account profile migrates secondary slot and pool state',
      () {
    final migrated = migrateKuaishouAccountBackup(
      {
        'cookie': 'userId=primary_user; token=primary',
        'kww': 'primary-kww',
        'cookieExpiresAt': 1000,
      },
      legacySettings: {
        LocalStorageService.kKuaishouSecondaryCookie:
            'userId=secondary_user; token=secondary',
        LocalStorageService.kKuaishouSecondaryKww: 'secondary-kww',
        LocalStorageService.kKuaishouSecondaryCookieExpiresAt: 2000,
        LocalStorageService.kKuaishouAccountPoolState: {
          'mode': 'secondary',
          'primary': {'credentialState': 'invalid'},
          'secondary': {'credentialState': 'valid'},
        },
      },
    );
    final slots = migrated['slots'] as Map;

    expect(migrated['mode'], 'secondary');
    expect((slots['primary'] as Map)['cookie'], contains('primary_user'));
    expect((slots['secondary'] as Map)['cookie'], contains('secondary_user'));
    expect(
      ((slots['secondary'] as Map)['state'] as Map)['credentialState'],
      'valid',
    );
  });

  test('explicit dual-account backup is copied without legacy fallback', () {
    final migrated = migrateKuaishouAccountBackup(
      {
        'mode': 'anonymous',
        'slots': {
          'primary': {
            'cookie': 'userId=primary_user; token=primary',
            'kww': 'primary-kww',
            'cookieExpiresAt': 1000,
          },
          'secondary': {
            'cookie': 'userId=secondary_user; token=secondary',
            'kww': 'secondary-kww',
            'cookieExpiresAt': 2000,
          },
        },
      },
      legacySettings: {
        LocalStorageService.kKuaishouSecondaryCookie: 'legacy-secondary',
      },
    );
    final slots = migrated['slots'] as Map;

    expect(migrated['mode'], 'anonymous');
    expect((slots['secondary'] as Map)['cookie'], contains('secondary_user'));
  });
}
