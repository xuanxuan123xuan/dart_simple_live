import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';

class _TestDouyuAccountService extends DouyuAccountService {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  String get summary => hasCookie.value ? '已配置斗鱼 Cookie' : '未配置 Cookie（可选）';
}

void main() {
  late _TestDouyuAccountService account;
  late AccountController controller;

  setUp(() {
    Get.testMode = true;
    account = _TestDouyuAccountService();
    Get.put<DouyuAccountService>(account);
    account.hasCookie.value = true;
    controller = Get.put<AccountController>(AccountController());
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    Get.reset();
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: controller.douyuLogin,
              child: const Text('打开斗鱼菜单'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开斗鱼菜单'));
    await tester.pumpAndSettle();
  }

  testWidgets('mobile account menu offers in-app login and file import', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await openMenu(tester);

    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('从文件导入 Cookie'), findsOneWidget);
    expect(find.text('浏览器登录后粘贴 Cookie'), findsNothing);
    expect(find.text('查看当前 Cookie'), findsOneWidget);
    expect(find.text('复制当前 Cookie'), findsOneWidget);
    expect(find.text('清除 Cookie'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop account menu directs to external browser and paste', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await openMenu(tester);

    expect(find.text('浏览器登录后粘贴 Cookie'), findsOneWidget);
    expect(find.text('网页登录'), findsNothing);
    expect(find.text('从文件导入 Cookie'), findsNothing);
    expect(find.text('手动粘贴 Cookie'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test('in-app login is offered on Android, iOS, and OHOS only', () {
    expect(
      douyuInAppLoginAvailable(TargetPlatform.android, isOhos: false),
      isTrue,
    );
    expect(
      douyuInAppLoginAvailable(TargetPlatform.iOS, isOhos: false),
      isTrue,
    );
    expect(
      douyuInAppLoginAvailable(TargetPlatform.linux, isOhos: true),
      isTrue,
    );
    expect(
      douyuInAppLoginAvailable(TargetPlatform.linux, isOhos: false),
      isFalse,
    );
    expect(
      douyuInAppLoginAvailable(TargetPlatform.windows, isOhos: false),
      isFalse,
    );
    expect(
      douyuInAppLoginAvailable(TargetPlatform.macOS, isOhos: false),
      isFalse,
    );
  });
}
