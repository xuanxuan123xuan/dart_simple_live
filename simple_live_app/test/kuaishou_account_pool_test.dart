import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

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

  test('temporary follow cooldown makes a configured account unavailable', () {
    final session = KuaishouAccountSession(KuaishouAccountSlot.primary)
      ..cookie = 'kuaishou.live.web_st=token'
      ..cooldownUntil = DateTime(2026, 8, 12, 12, 5);

    expect(session.isAvailable(DateTime(2026, 8, 12, 12)), isFalse);
    expect(session.isAvailable(DateTime(2026, 8, 12, 12, 6)), isTrue);
  });

  test('expired anonymous cooldown reactivates the site account transport',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'kuaishou_account_pool_test_',
    );
    Hive.init(tempDirectory.path);
    final storage = LocalStorageService();
    await storage.init();
    Get.put<LocalStorageService>(storage);
    final site = KuaishouSite();
    final account = KuaishouAccountService(site: site);
    account.primary
      ..cookie = 'userId=primary_user; token=primary'
      ..cooldownUntil = DateTime(2026, 8, 12, 12, 5);
    account.mode.value = KuaishouAccountPoolMode.anonymous;
    site.activateAnonymousMode();

    account.refreshAvailability(DateTime(2026, 8, 12, 12, 6));

    expect(account.mode.value, KuaishouAccountPoolMode.primary);
    expect(site.anonymousMode, isFalse);
    expect(site.activeAccountSessionKey, KuaishouAccountSlot.primary.name);

    final secondarySite = KuaishouSite();
    final secondaryAccount = KuaishouAccountService(site: secondarySite);
    secondaryAccount.primary
      ..cookie = 'userId=primary_user; token=primary'
      ..cooldownUntil = DateTime(2026, 8, 12, 12, 5);
    secondaryAccount.secondary.cookie =
        'userId=secondary_user; token=secondary';
    secondaryAccount.mode.value = KuaishouAccountPoolMode.secondary;
    secondaryAccount.setSite();

    secondaryAccount.refreshAvailability(DateTime(2026, 8, 12, 12, 6));

    expect(
      secondaryAccount.mode.value,
      KuaishouAccountPoolMode.secondary,
      reason: 'a recovered primary must not steal mode from a healthy fallback',
    );
    expect(
      secondarySite.activeAccountSessionKey,
      KuaishouAccountSlot.secondary.name,
    );

    expect(
      secondaryAccount.activateRebuiltSession(
        KuaishouAccountSlot.primary,
        now: DateTime(2026, 8, 12, 12, 6),
      ),
      isTrue,
    );
    expect(secondaryAccount.mode.value, KuaishouAccountPoolMode.primary);
    expect(
      secondarySite.activeAccountSessionKey,
      KuaishouAccountSlot.primary.name,
    );

    await Hive.close();
    await tempDirectory.delete(recursive: true);
    Get.reset();
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

  test('credential cookie removes device fields but keeps login fields', () {
    final sanitized = sanitizeKuaishouCredentialCookie(
      'did=device-a; DIDV=device-b; clientid=client-a; '
      'client_key=key-a; kpn=GAME_ZONE; kuaishou.live.bfb1s=marker; '
      'kuaishou.live.web_st=login-token; userId=user-1; kwfv1=keep; '
      'unknown=value',
    );

    expect(sanitized, isNot(contains('did=')));
    expect(sanitized.toLowerCase(), isNot(contains('didv=')));
    expect(sanitized, isNot(contains('clientid=')));
    expect(sanitized, isNot(contains('client_key=')));
    expect(sanitized, isNot(contains('kpn=')));
    expect(sanitized, isNot(contains('kuaishou.live.bfb1s=')));
    expect(sanitized, contains('kuaishou.live.web_st=login-token'));
    expect(sanitized, contains('userId=user-1'));
    expect(sanitized, contains('kwfv1=keep'));
    expect(sanitized, contains('unknown=value'));
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
      ..cookie = 'did=old-device; userId=backup_user; token=secondary'
      ..kww = 'secondary-kww'
      ..cookieExpiresAt = DateTime(2026, 9, 1)
      ..credentialState = KuaishouCredentialState.valid
      ..loggedInAt = DateTime(2026, 8, 1)
      ..lastValidatedAt = DateTime(2026, 8, 8)
      ..suspendedUntil = suspendedUntil
      ..suspendedReason = 'rateLimited';
    final restored = KuaishouAccountSession(KuaishouAccountSlot.secondary)
      ..restoreBackup(source.toBackupJson());

    expect(restored.cookie, 'userId=backup_user; token=secondary');
    expect(
      (source.toBackupJson()['cookie'] as String),
      isNot(contains('did=')),
    );
    expect(restored.kww, source.kww);
    expect(restored.cookieExpiresAt, source.cookieExpiresAt);
    expect(restored.credentialState, KuaishouCredentialState.valid);
    expect(restored.lastValidatedAt, source.lastValidatedAt);
    expect(restored.suspendedUntil, suspendedUntil);
    expect(restored.suspendedReason, 'rateLimited');
  });

  test('restoring a legacy backup sanitizes device cookies', () {
    final restored = KuaishouAccountSession(KuaishouAccountSlot.primary)
      ..restoreBackup({
        'cookie':
            'did=old-device; clientid=old-client; userId=user-1; token=login',
        'kww': 'credential',
        'state': const <String, dynamic>{},
      });

    expect(restored.cookie, 'userId=user-1; token=login');
    expect(restored.kww, 'credential');
  });

  test('device rebuild limit follows Shanghai calendar day and stays local',
      () {
    final rebuiltAt = DateTime.utc(2026, 8, 29, 15, 30);
    final session = KuaishouAccountSession(KuaishouAccountSlot.primary)
      ..cookie = 'userId=user-1; token=login'
      ..lastDeviceSessionRebuiltAt = rebuiltAt;
    final service = KuaishouAccountService();
    service.primary
      ..cookie = session.cookie
      ..lastDeviceSessionRebuiltAt = rebuiltAt;

    expect(
      service.canRebuildDeviceSession(
        KuaishouAccountSlot.primary,
        now: DateTime.utc(2026, 8, 29, 15, 59),
      ),
      isFalse,
    );
    expect(
      service.canRebuildDeviceSession(
        KuaishouAccountSlot.primary,
        now: DateTime.utc(2026, 8, 29, 16),
      ),
      isTrue,
    );

    final localState = session.toStateJson();
    final backupState = session.toBackupJson()['state'] as Map;
    final restored = KuaishouAccountSession(KuaishouAccountSlot.primary)
      ..restoreState(localState);
    expect(localState['lastDeviceSessionRebuiltAt'], isNotNull);
    expect(restored.lastDeviceSessionRebuiltAt, rebuiltAt);
    expect(backupState, isNot(contains('lastDeviceSessionRebuiltAt')));
  });

  test('stored legacy cookies are sanitized when the account service loads',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'kuaishou_cookie_migration_test_',
    );
    Hive.init(tempDirectory.path);
    final storage = LocalStorageService();
    await storage.init();
    await storage.setValue(
      LocalStorageService.kKuaishouCookie,
      'did=old-primary; userId=primary; token=login',
    );
    await storage.setValue(
      LocalStorageService.kKuaishouSecondaryCookie,
      'clientid=old-secondary; userId=secondary; token=login-2',
    );
    Get.put<LocalStorageService>(storage);
    final account = KuaishouAccountService(site: KuaishouSite());

    account.onInit();
    await Future<void>.delayed(Duration.zero);

    expect(account.primary.cookie, 'userId=primary; token=login');
    expect(account.secondary.cookie, 'userId=secondary; token=login-2');
    expect(
      storage.getValue(LocalStorageService.kKuaishouCookie, ''),
      account.primary.cookie,
    );
    expect(
      storage.getValue(LocalStorageService.kKuaishouSecondaryCookie, ''),
      account.secondary.cookie,
    );

    await Hive.close();
    await tempDirectory.delete(recursive: true);
    Get.reset();
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
