import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';

void main() {
  test('TV danmaku options include larger and slower readability choices', () {
    expect(AppSettingsController.tvDanmuSizeOptions.keys, contains(80.0));
    expect(AppSettingsController.tvDanmuSizeOptions.keys, contains(88.0));
    expect(AppSettingsController.tvDanmuSizeOptions.keys, contains(96.0));
    expect(AppSettingsController.tvDanmuSizeOptions[96.0], '96');

    expect(AppSettingsController.tvDanmuSpeedOptions.keys, contains(22.0));
    expect(AppSettingsController.tvDanmuSpeedOptions.keys, contains(26.0));
    expect(AppSettingsController.tvDanmuSpeedOptions.keys, contains(30.0));
    expect(AppSettingsController.tvDanmuSpeedOptions[30.0], '阅读');
  });
}
