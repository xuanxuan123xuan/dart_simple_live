import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_room_tab_bar.dart';

void main() {
  testWidgets('tap switches back after swiping to another tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final selections = <int>[];
    final changes = <int>[];
    TabController? tabController;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) {
              tabController = DefaultTabController.of(context);
              return Column(
                children: [
                  LiveRoomTabBar(
                    controller: tabController!,
                    labels: const ['Chat', 'Follow', 'Settings'],
                    keys: const ['chat', 'follow', 'settings'],
                    onTabSelected: (index) {
                      selections.add(index);
                      tabController!.animateTo(index);
                    },
                    onTabChanged: changes.add,
                    iconBuilder: (_, active) =>
                        active ? Icons.circle : Icons.circle_outlined,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: const [
                        Center(child: Text('Chat page')),
                        Center(child: Text('Follow page')),
                        Center(child: Text('Settings page')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('Chat page'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tabController!.index, 1);
    expect(find.text('Follow page'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(tabController!.index, 0);
    expect(find.text('Chat page'), findsOneWidget);

    await tester.drag(find.text('Chat page'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tabController!.index, 2);
    expect(find.text('Settings page'), findsOneWidget);
    expect(selections, [0, 2]);
    expect(changes, [0, 1, 0, 1, 2]);
  });

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
