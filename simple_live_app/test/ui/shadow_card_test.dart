import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';

void main() {
  testWidgets('transparent shadow cards keep transparent fallback surfaces',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const ShadowCard(
          backgroundColor: Colors.transparent,
          child: SizedBox.square(dimension: 48),
        ),
      ),
    );

    final material = tester.widget<Material>(find.byType(Material).first);
    expect(material.color, Colors.transparent);
  });
}
