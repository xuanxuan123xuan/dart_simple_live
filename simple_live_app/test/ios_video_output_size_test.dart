import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ios_video_output_size.dart';

void main() {
  test('keeps source size when it already fits the physical screen', () {
    final size = calculateIosVideoOutputSize(
      sourceWidth: 1280,
      sourceHeight: 720,
      screenPhysicalWidth: 2556,
      screenPhysicalHeight: 1179,
    );

    expect(size, const IosVideoOutputSize(1280, 720));
  });

  test('limits a large source to the physical screen while preserving aspect',
      () {
    final size = calculateIosVideoOutputSize(
      sourceWidth: 3840,
      sourceHeight: 2160,
      screenPhysicalWidth: 2556,
      screenPhysicalHeight: 1179,
    );

    expect(size, const IosVideoOutputSize(2096, 1178));
  });

  test('rounds output dimensions down to even values', () {
    final size = calculateIosVideoOutputSize(
      sourceWidth: 1921,
      sourceHeight: 1081,
      screenPhysicalWidth: 1001,
      screenPhysicalHeight: 1001,
    );

    expect(size, const IosVideoOutputSize(1000, 562));
  });

  test('rejects invalid source or screen sizes', () {
    expect(
      calculateIosVideoOutputSize(
        sourceWidth: 0,
        sourceHeight: 1080,
        screenPhysicalWidth: 2556,
        screenPhysicalHeight: 1179,
      ),
      isNull,
    );
    expect(
      calculateIosVideoOutputSize(
        sourceWidth: 1920,
        sourceHeight: 1080,
        screenPhysicalWidth: double.nan,
        screenPhysicalHeight: 1179,
      ),
      isNull,
    );
  });
}
