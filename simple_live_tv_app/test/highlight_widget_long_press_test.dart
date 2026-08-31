import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/widgets/highlight_widget.dart';

void main() {
  testWidgets('short select activates tap and long select suppresses tap', (
    tester,
  ) async {
    final focusNode = AppFocusNode();
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightWidget(
            focusNode: focusNode,
            autofocus: true,
            onTap: () => taps += 1,
            onLongPress: () => longPresses += 1,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, 1);
    expect(longPresses, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    expect(longPresses, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    focusNode.dispose();
  });
}
