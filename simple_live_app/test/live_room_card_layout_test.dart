import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  testWidgets('live room cover keeps a 16:9 aspect ratio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 396,
          child: LiveRoomCard(
            Sites.allSites.values.first,
            LiveRoomItem(
              roomId: 'room',
              title: 'Room',
              cover: '',
              userName: 'User',
            ),
          ),
        ),
      ),
    );

    final cover = tester.getSize(find.byType(AspectRatio));
    expect(cover.width / cover.height, closeTo(16 / 9, 0.001));
  });
}
