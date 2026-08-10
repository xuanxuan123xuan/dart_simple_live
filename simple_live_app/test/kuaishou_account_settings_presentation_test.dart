import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/mine/account/kuaishou/account_page.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';

class _TestKuaishouAccountService extends KuaishouAccountService {
  // The production hook requires Hive; presentation tests intentionally use
  // only the in-memory account sessions.
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late KuaishouAccountService account;
  late AccountController controller;

  setUp(() {
    Get.testMode = true;
    account = Get.put<KuaishouAccountService>(
      _TestKuaishouAccountService(),
    );
    controller = AccountController();
  });

  tearDown(Get.reset);

  test('settings summary exposes the current anonymous mode', () {
    account.mode.value = KuaishouAccountPoolMode.anonymous;

    expect(controller.getKuaishouCookieSummaryText(), '当前模式：匿名模式');
  });

  test('settings summary distinguishes daily suspension from expiry', () {
    account.primary
      ..cookie = 'userId=primary_user; token=primary'
      ..cookieExpiresAt = DateTime.now().add(const Duration(days: 5))
      ..suspendedUntil = DateTime.now().add(const Duration(hours: 2));

    expect(
      controller.getKuaishouSlotSummaryText(KuaishouAccountSlot.primary),
      startsWith('请求频繁，暂停至 '),
    );
  });

  test('settings summary exposes invalid and unknown-expiry states', () {
    account.primary
      ..cookie = 'userId=primary_user; token=primary'
      ..credentialState = KuaishouCredentialState.invalid;
    account.secondary
      ..cookie = 'userId=secondary_user; token=secondary'
      ..credentialState = KuaishouCredentialState.valid
      ..cookieExpiresAt = null;

    expect(
      controller.getKuaishouSlotSummaryText(KuaishouAccountSlot.primary),
      '已失效，请重新登录',
    );
    expect(
      controller.getKuaishouSlotSummaryText(KuaishouAccountSlot.secondary),
      contains('有效，到期时间未知'),
    );
  });

  testWidgets('Kuaishou account page shows primary and backup accounts', (
    tester,
  ) async {
    account.mode.value = KuaishouAccountPoolMode.anonymous;

    await tester.pumpWidget(
      const GetMaterialApp(home: KuaishouAccountPage()),
    );

    expect(find.text('快手账号'), findsOneWidget);
    expect(find.text('主账号'), findsOneWidget);
    expect(find.text('备用账号'), findsOneWidget);
    expect(find.text('当前模式：匿名模式'), findsOneWidget);
  });
}
