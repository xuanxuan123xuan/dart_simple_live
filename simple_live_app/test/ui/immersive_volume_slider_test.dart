import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/immersive_volume_slider.dart';

void main() {
  testWidgets('immersive slider keeps compact glass styling and callbacks',
      (tester) async {
    var muted = false;
    double? changedVolume;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ImmersiveVolumeSlider(
              value: 120,
              onChanged: (value) => changedVolume = value,
              onMute: () => muted = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      tester.getSize(find.byType(ImmersiveVolumeSlider)),
      const Size(
        ImmersiveVolumeSlider.width,
        ImmersiveVolumeSlider.height,
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 100);
    slider.onChanged?.call(63);
    expect(changedVolume, 63);

    await tester.tap(find.byTooltip("静音"));
    expect(muted, isTrue);
  });
}
