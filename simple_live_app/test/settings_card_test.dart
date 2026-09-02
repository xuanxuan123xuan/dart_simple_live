import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

void main() {
  testWidgets('SettingsCard keeps content visible when its child grows',
      (tester) async {
    final showExtra = ValueNotifier<bool>(false);
    addTearDown(showExtra.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ValueListenableBuilder<bool>(
                valueListenable: showExtra,
                builder: (context, expanded, _) => SettingsCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        height: 56,
                        child: Text('base'),
                      ),
                      if (expanded)
                        const SizedBox(
                          key: ValueKey<String>('settings-card-expanded'),
                          height: 56,
                          child: Text('expanded'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('settings-card-expanded')),
        findsNothing);
    showExtra.value = true;
    await tester.pump();

    expect(tester.takeException(), isNull);
    final expanded =
        find.byKey(const ValueKey<String>('settings-card-expanded'));
    expect(expanded, findsOneWidget);
    expect(tester.getSize(expanded).height, 56);
  });
}
