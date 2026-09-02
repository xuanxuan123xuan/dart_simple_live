import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';

void main() {
  group('AppGlassMode', () {
    test('uses stable storage values and the requested display labels', () {
      expect(
        AppGlassMode.values.map((mode) => mode.storageValue),
        ['off', 'auto', 'minimal', 'standard', 'premium'],
      );
      expect(
        AppGlassMode.values.map((mode) => mode.label),
        ['关闭', '自动', '轻量', '标准', '高质量'],
      );
    });

    test('defaults missing or unknown values to auto', () {
      expect(AppGlassMode.defaultMode, AppGlassMode.auto);
      expect(AppGlassMode.fromStorage(null), AppGlassMode.auto);
      expect(AppGlassMode.fromStorage(''), AppGlassMode.auto);
      expect(AppGlassMode.fromStorage('future-value'), AppGlassMode.auto);
    });

    test('round-trips every mode through storage', () {
      for (final mode in AppGlassMode.values) {
        expect(AppGlassMode.fromStorage(mode.storageValue), mode);
      }
    });
  });
}
