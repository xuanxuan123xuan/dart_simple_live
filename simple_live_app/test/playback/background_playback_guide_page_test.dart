import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/settings/background_playback_guide_page.dart';

void main() {
  testWidgets('shows general and vendor background playback guidance',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(
      home: BackgroundPlaybackGuidePage(),
    ));

    expect(find.text('后台播放保活指南'), findsOneWidget);
    expect(find.text('电池优化'), findsOneWidget);
    expect(find.text('应用电池管理'), findsOneWidget);
    expect(find.text('自启动管理'), findsOneWidget);
    expect(find.text('通知权限'), findsOneWidget);
    expect(find.text('小米 / Redmi'), findsOneWidget);
    expect(find.text('OPPO / 真我'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('vivo'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    expect(find.text('vivo'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('华为'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    expect(find.text('华为'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('荣耀'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    expect(find.text('荣耀'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('魅族'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    expect(find.text('魅族'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('三星 / 原生 Android'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    expect(find.text('三星 / 原生 Android'), findsOneWidget);
  });
}
