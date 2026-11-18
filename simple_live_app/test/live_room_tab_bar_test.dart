import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_room_tab_bar.dart';

void main() {
  testWidgets('renders tab labels and reports taps by index', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final selections = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) {
              final controller = DefaultTabController.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  child: LiveRoomTabBar(
                    controller: controller,
                    labels: const ['聊天', 'SC', '设置'],
                    keys: const ['chat', 'super_chat', 'settings'],
                    onTabSelected: selections.add,
                    iconBuilder: (_, active) =>
                        active ? Icons.circle : Icons.circle_outlined,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('SC'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-room-tab-indicator')),
      findsOneWidget,
    );

    await tester.tap(find.text('设置'));
    await tester.pump();

    expect(selections, [2]);
  });
}
