import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/guide_service.dart';

void main() {
  testWidgets(
    'tracked focus rect stays aligned during transformed page transitions',
    (tester) async {
      final guide = GuideService();
      final targetKey = GlobalKey();
      final transitionOffset = ValueNotifier<double>(72);
      addTearDown(transitionOffset.dispose);
      addTearDown(guide.dismiss);

      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                left: 20,
                top: 10,
                child: SizedBox(
                  key: guide.overlayKey,
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: transitionOffset,
                builder: (context, offset, child) {
                  return Positioned(
                    left: 32,
                    top: 24,
                    child: Transform.translate(
                      offset: Offset(offset, 0),
                      child: SizedBox(
                        key: targetKey,
                        width: 180,
                        height: 48,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

      guide.startSearchGuide();
      guide.trackFocusRectFromKey(targetKey);
      await tester.pump();

      expect(guide.focusRect.value, const Rect.fromLTWH(84, 14, 180, 48));

      transitionOffset.value = 0;
      await tester.pump();

      expect(guide.focusRect.value, const Rect.fromLTWH(12, 14, 180, 48));
    },
  );
}
