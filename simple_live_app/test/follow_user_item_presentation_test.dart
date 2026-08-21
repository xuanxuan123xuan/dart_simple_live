import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/net_image.dart';

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

  testWidgets(
    'covered list layouts keep metadata inside the cover height',
    (tester) async {
      for (final layout in <(FollowUserItemStyle, double)>[
        (FollowUserItemStyle.defaultList, 94),
        (FollowUserItemStyle.compactList, 77),
      ]) {
        final item = _followUser()
          ..face = 'asset://assets/images/bilibili.png'
          ..roomCover = 'asset://assets/images/logo.png'
          ..liveStatus.value = 2;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: SizedBox(
                  width: 420,
                  height: layout.$2,
                  child: FollowUserItem(
                    item: item,
                    style: layout.$1,
                    showLiveCover: true,
                    onSpecialTap: () {},
                    onRemove: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '${layout.$1} must fit within ${layout.$2}px',
        );
        expect(find.text('直播间'), findsOneWidget);
        expect(find.text('直播中'), findsNothing);

        final coverRect = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is NetImage &&
                widget.picUrl == 'asset://assets/images/logo.png',
          ),
        );
        final avatarRect = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is NetImage &&
                widget.picUrl == 'asset://assets/images/bilibili.png',
          ),
        );
        expect(avatarRect.center.dx, closeTo(coverRect.right, 0.01));
        expect(avatarRect.center.dy, closeTo(coverRect.center.dy, 0.01));
      }
    },
  );

  testWidgets('offline covered layouts group user id above platform', (
    tester,
  ) async {
    for (final layout in <(FollowUserItemStyle, double)>[
      (FollowUserItemStyle.defaultList, 94),
      (FollowUserItemStyle.compactList, 77),
    ]) {
      final item = _followUser()
        ..face = 'asset://assets/images/bilibili.png'
        ..liveStatus.value = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: layout.$2,
              child: FollowUserItem(
                item: item,
                style: layout.$1,
                showLiveCover: true,
                onSpecialTap: () {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('直播间'), findsNothing);
      expect(find.text('主播'), findsOneWidget);
      final userIdRect = tester.getRect(find.text('主播'));
      final platformLogoRect = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/bilibili_2.png',
        ),
      );
      final cardCenterY = tester.getCenter(find.byType(FollowUserItem)).dy;
      expect(userIdRect.left, closeTo(platformLogoRect.left, 0.01));
      expect(platformLogoRect.top - userIdRect.bottom, inInclusiveRange(1, 4));
      expect(
        (userIdRect.top + platformLogoRect.bottom) / 2,
        closeTo(cardCenterY, 1),
      );
    }
  });

  testWidgets('unconfirmed covered list layout shows status on cover', (
    tester,
  ) async {
    final item = _followUser()
      ..face = 'asset://assets/images/bilibili.png'
      ..liveStatus.value = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 94,
            child: FollowUserItem(
              item: item,
              showLiveCover: true,
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('未确认'), findsOneWidget);
  });

  testWidgets('offline covered list layouts label the cover placeholder', (
    tester,
  ) async {
    for (final layout in <(FollowUserItemStyle, double, double)>[
      (FollowUserItemStyle.defaultList, 94, 152),
      (FollowUserItemStyle.compactList, 77, 122),
    ]) {
      for (final textScale in <double>[1.0, 1.3]) {
        final item = _followUser()
          ..face = 'asset://assets/images/bilibili.png'
          ..liveStatus.value = 1;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: SizedBox(
                  width: 420,
                  height: layout.$2,
                  child: FollowUserItem(
                    item: item,
                    style: layout.$1,
                    showLiveCover: true,
                    onRemove: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('未直播'), findsOneWidget);
        // 占位文字必须落在封面区域内，不能溢出到信息列。
        final statusRect = tester.getRect(find.text('未直播'));
        expect(statusRect.width, lessThanOrEqualTo(layout.$3));
        expect(statusRect.height, lessThanOrEqualTo(layout.$3 * 9 / 16));
      }
    }
  });

  testWidgets('covered card floats actions on the cover and frees the name', (
    tester,
  ) async {
    // 操作按钮若留在正文，M3 IconButton 会把名字行撑到 40px 并在名字与标题间
    // 留下大段空白；星标开启后两个按钮还会把窄屏名字挤成省略号。
    for (final textScale in <double>[1.0, 1.3, 2.0]) {
      for (final cardWidth in <double>[146.0, 191.5]) {
        final bodyExtent = (72.0 + (textScale - 1.0) * 28.0).clamp(72.0, 94.0);
        final coverHeight = cardWidth * 9 / 16;
        // 名字取足够长的串，确保它会填满可用宽度而非按内容收缩。
        const longName = '主播名字很长很长很长很长';
        final item = _followUser()
          ..userName = longName
          ..face = 'asset://assets/images/bilibili.png'
          ..roomCover = 'asset://assets/images/logo.png'
          ..isSpecialFollow = true
          ..liveStatus.value = 2;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: cardWidth,
                    height: coverHeight + bodyExtent,
                    child: FollowUserItem(
                      item: item,
                      style: FollowUserItemStyle.card,
                      showLiveCover: true,
                      showSpecialMark: true,
                      onSpecialTap: () {},
                      onRemove: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final reason = 'scale=$textScale width=$cardWidth';
        expect(tester.takeException(), isNull, reason: reason);

        final cardRect = tester.getRect(find.byType(FollowUserItem));
        final removeBtn = tester.getRect(
          find.ancestor(
            of: find.byIcon(Remix.dislike_line),
            matching: find.byType(IconButton),
          ),
        );
        final starBtn = tester.getRect(
          find.ancestor(
            of: find.byIcon(Icons.star),
            matching: find.byType(IconButton),
          ),
        );

        // 两个按钮并排浮在封面右上角，不占正文高度，点击区保持 36px。
        expect(removeBtn.height, 36, reason: reason);
        expect(starBtn.height, 36, reason: reason);
        expect(starBtn.center.dy, closeTo(removeBtn.center.dy, 0.01),
            reason: reason);
        expect(
          removeBtn.bottom,
          lessThanOrEqualTo(cardRect.top + coverHeight),
          reason: reason,
        );
        expect(
          removeBtn.right,
          lessThanOrEqualTo(cardRect.right),
          reason: reason,
        );
        expect(starBtn.left, greaterThanOrEqualTo(cardRect.left),
            reason: reason);

        // 特别关注状态只呈现一次，平台行不再重复画星标。
        expect(find.byIcon(Icons.star), findsOneWidget, reason: reason);

        // 名字行拿到整宽：卡片内宽减去头像占位，不再被按钮切掉 56px。
        final nameRect = tester.getRect(find.text(longName));
        expect(
          nameRect.width,
          closeTo(cardWidth - 12 * 2 - (44 + 8), 0.01),
          reason: reason,
        );

        // 名字行与标题之间不得再出现大段空白。
        final titleRect = tester.getRect(find.text('直播间'));
        expect(
          titleRect.top - nameRect.bottom,
          inInclusiveRange(0, 14),
          reason: reason,
        );
      }
    }
  });

  testWidgets('hidden special action leaves remove action vertically centered',
      (
    tester,
  ) async {
    final item = _followUser()
      ..face = 'asset://assets/images/bilibili.png'
      ..isSpecialFollow = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 94,
            child: FollowUserItem(
              item: item,
              showLiveCover: true,
              showSpecialMark: false,
              onSpecialTap: () {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
    expect(tester.takeException(), isNull);

    final itemCenter = tester.getCenter(find.byType(FollowUserItem));
    final removeCenter = tester.getCenter(find.byIcon(Remix.dislike_line));
    expect(removeCenter.dy, closeTo(itemCenter.dy, 0.01));
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
