import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_room_follow_filter_bar.dart';

void main() {
  testWidgets('fallback renders labels and reports selected index', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              LiveRoomFollowFilterBar(
                selectedIndex: selectedIndex,
                onSelected: (index) {
                  setState(() => selectedIndex = index);
                },
              ),
              const SizedBox(height: 16),
              const SizedBox(
                key: ValueKey('first-follow-user'),
                height: 48,
                child: ColoredBox(color: Colors.blue),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('直播中'), findsOneWidget);
    expect(find.text('未开播'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-room-follow-filter-fallback')),
      findsOneWidget,
    );

    final filterRect = tester.getRect(
      find.byKey(const ValueKey('live-room-follow-filter-fallback')),
    );
    expect(filterRect.width, closeTo(344, 0.01));
    final firstItemRect = tester.getRect(
      find.byKey(const ValueKey('first-follow-user')),
    );
    expect(firstItemRect.top - filterRect.bottom, closeTo(16, 0.01));

    await tester.tap(find.text('未开播'));
    await tester.pump();
    expect(selectedIndex, 2);
  });
}
