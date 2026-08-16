import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';

void main() {
  testWidgets('dark follow card uses a visible themed surface and frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppStyle.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 100,
            child: FollowUserItem(item: _followUser()),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FollowUserItem),
            matching: find.byType(Material),
          )
          .first,
    );
    final decoration = _frameDecoration(tester);
    final border = decoration.border! as Border;
    final colorScheme = AppStyle.darkTheme.colorScheme;

    expect(material.color, colorScheme.surfaceContainerHigh);
    expect(border.top.color, colorScheme.outlineVariant.withAlpha(230));
    expect(border.top.width, 1);
  });

  testWidgets('selected preview card paints a complete foreground frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppStyle.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 340,
            child: FollowUserItem(
              item: _followUser(),
              style: FollowUserItemStyle.card,
              showLiveCover: true,
              playing: true,
            ),
          ),
        ),
      ),
    );

    final decoration = _frameDecoration(tester);
    final border = decoration.border! as Border;

    expect(border.isUniform, isTrue);
    expect(border.top.color, AppStyle.darkTheme.colorScheme.primary);
    expect(border.top.width, 2);
  });
}

BoxDecoration _frameDecoration(WidgetTester tester) {
  final containers = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(FollowUserItem),
          matching: find.byType(Container),
        ),
      )
      .where((container) => container.foregroundDecoration is BoxDecoration);
  expect(containers, hasLength(1));
  return containers.single.foregroundDecoration! as BoxDecoration;
}

FollowUser _followUser() {
  return FollowUser(
    id: 'bilibili_room',
    roomId: 'room',
    siteId: Constant.kBiliBili,
    userName: '主播',
    face: '',
    addTime: DateTime(2026),
    roomTitle: '直播间',
  );
}
