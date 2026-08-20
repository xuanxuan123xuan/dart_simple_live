import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/modules/settings/settings_controller.dart';
import 'package:simple_live_tv_app/services/kuaishou_account_service.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

class _TestKuaishouAccountService extends KuaishouAccountService {
  @override
  // Presentation tests intentionally avoid Hive and the live-site hook.
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  test('configured invalid account never becomes available', () {
    final session = KuaishouAccountSession(KuaishouAccountSlot.primary)
      ..cookie = 'kuaishou.live.web_st=token'
      ..credentialState = KuaishouCredentialState.invalid
      ..suspendedUntil = DateTime(2026, 1, 2);

    expect(session.isAvailable(DateTime(2026, 1, 3)), isFalse);
  });

  test('cookie comparison ignores ordering and whitespace', () {
    expect(
      normalizeKuaishouCookie('b=2; a=1'),
      normalizeKuaishouCookie(' a=1;b=2 '),
    );
  });

  test('request headers input extracts Cookie and Kww', () {
    const input =
        'Host: live.kuaishou.com\n'
        'Cookie: userId=account_123; kwfv1=cookie-sign\n'
        'Kww: header-sign';

    expect(
      normalizeKuaishouCookieInput(input),
      'userId=account_123; kwfv1=cookie-sign',
    );
    expect(extractKuaishouKwwFromInput(input), 'header-sign');
    expect(
      kuaishouCookieHasKey(normalizeKuaishouCookieInput(input), 'kwfv1'),
      isTrue,
    );
  });

  test('legacy profile migrates the secondary account and active mode', () {
    final migrated = migrateKuaishouAccountBackup(
      {'cookie': 'userId=primary_user; token=primary', 'kww': 'primary-kww'},
      legacySettings: {
        LocalStorageService.kKuaishouSecondaryCookie:
            'userId=secondary_user; token=secondary',
        LocalStorageService.kKuaishouSecondaryKww: 'secondary-kww',
        LocalStorageService.kKuaishouAccountPoolState: {'mode': 'secondary'},
      },
    );
    final slots = migrated['slots'] as Map;

    expect(migrated['mode'], 'secondary');
    expect((slots['primary'] as Map)['cookie'], contains('primary_user'));
    expect((slots['secondary'] as Map)['cookie'], contains('secondary_user'));
  });

  group('TV settings presentation', () {
    late KuaishouAccountService account;
    late SettingsController controller;

    setUp(() {
      Get.testMode = true;
      account = Get.put<KuaishouAccountService>(_TestKuaishouAccountService());
      controller = SettingsController();
    });

    tearDown(() {
      controller.onClose();
      Get.reset();
    });

    test('summary exposes both account slots and active mode', () {
      account.primary.cookie = 'userId=primary_user; token=primary';
      account.secondary.cookie = 'userId=secondary_user; token=secondary';
      account.mode.value = KuaishouAccountPoolMode.secondary;

      expect(
        controller.getKuaishouAccountSummaryText(),
        '当前：备用账号；已配置 2/2，异常时自动切换',
      );
      expect(
        controller.getKuaishouSlotSummaryText(KuaishouAccountSlot.secondary),
        '已配置，待验证',
      );
    });
  });
}
