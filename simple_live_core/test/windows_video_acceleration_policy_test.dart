import 'package:test/test.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('hardware decode off always selects software decode', () {
    final result = WindowsVideoAccelerationPolicy.resolve(
      hardwareDecode: false,
      renderingAcceleration: true,
      requestedHwdec: 'd3d11va',
    );
    expect(result.hwdec, 'no');
  });

  test('copy-back mode maps GPU decoders to CPU-accessible frames', () {
    final result = WindowsVideoAccelerationPolicy.resolve(
      hardwareDecode: true,
      renderingAcceleration: false,
      requestedHwdec: 'd3d11va',
    );
    expect(result.hwdec, 'd3d11va-copy');
  });

  test('software decoder remains unchanged in copy-back mode', () {
    final result = WindowsVideoAccelerationPolicy.resolve(
      hardwareDecode: true,
      renderingAcceleration: false,
      requestedHwdec: 'auto-copy',
    );
    expect(result.hwdec, 'auto-copy');
  });

  test('unknown decoder safely falls back to software', () {
    final result = WindowsVideoAccelerationPolicy.resolve(
      hardwareDecode: true,
      renderingAcceleration: false,
      requestedHwdec: 'unknown-decoder',
    );
    expect(result.hwdec, 'no');
  });
}
