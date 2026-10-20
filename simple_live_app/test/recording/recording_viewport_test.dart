import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/recording/recording_viewport.dart';

void main() {
  test('contain preserves video aspect and accounts for danmaku padding', () {
    expect(
        recordingVideoRect(
            source: const Size(160, 90),
            viewport: const Size(200, 200),
            fit: BoxFit.contain,
            danmakuOrigin: const Offset(0, 10)),
        const Rect.fromLTWH(0, 33.75, 200, 112.5));
  });
  test('cover maps the entire source outside cropped viewport bounds', () {
    expect(
        recordingVideoRect(
            source: const Size(200, 100),
            viewport: const Size(100, 100),
            fit: BoxFit.cover),
        const Rect.fromLTWH(-50, 0, 200, 100));
  });
  test(
      'fill uses the displayed stretch while source output keeps original size',
      () {
    expect(
        recordingVideoRect(
            source: const Size(200, 100),
            viewport: const Size(100, 100),
            fit: BoxFit.fill),
        const Rect.fromLTWH(0, 0, 100, 100));
  });
}
