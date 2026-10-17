import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';

void main() {
  test('ordinary and compatibility Android configurations retain callback', () {
    void diagnostic(String event, Map<String, Object?> fields) {}

    final ordinary = MpvOptionsService.androidVideoControllerConfiguration(
      compatibilityMode: false,
      hardwareDecode: true,
      vo: 'gpu',
      hwdec: 'auto-safe',
      onDiagnostic: diagnostic,
    );
    final compatibility = MpvOptionsService.androidVideoControllerConfiguration(
      compatibilityMode: true,
      hardwareDecode: true,
      vo: 'gpu',
      hwdec: 'auto-safe',
      onDiagnostic: diagnostic,
    );

    expect(ordinary.onDiagnostic, same(diagnostic));
    expect(compatibility.onDiagnostic, same(diagnostic));
    expect(
      compatibility.copyWith(hwdec: 'mediacodec').onDiagnostic,
      same(diagnostic),
    );
    expect(compatibility.vo, 'mediacodec_embed');
    expect(compatibility.hwdec, 'mediacodec');
  });
}
