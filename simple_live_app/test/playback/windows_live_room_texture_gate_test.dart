import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows auto line selection waits for a ready video texture', () {
    final source = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<void> _selectFastestLineAfterPlaybackStart(',
    );
    final end = source.indexOf(
      'Future<void> initPlaylist(',
      start,
    );
    final method = source.substring(start, end);

    final readiness = method.indexOf('_waitForDesktopVideoOutputReady(');
    final diagnosis = method.indexOf(
      'NetworkDiagnoseService.findFastestLine(candidates)',
    );
    expect(readiness, greaterThanOrEqualTo(0));
    expect(diagnosis, greaterThan(readiness));
    expect(
      source,
      contains("final rect = videoController.rect.value;"),
    );
    expect(source, contains('Windows 视频纹理就绪超时，跳过后台换线'));
    expect(source, contains('_desktopVideoOutputReadyTimeout'));
  });

  test('Windows video output drains texture work before destruction', () {
    final header = File(
      '../third_party/media_kit_video/windows/video_output.h',
    ).readAsStringSync();
    final source = File(
      '../third_party/media_kit_video/windows/video_output.cc',
    ).readAsStringSync();

    expect(header, contains('std::atomic_bool destroyed_{false}'));
    expect(header, contains('std::shared_ptr<std::atomic_bool> lifetime_'));
    expect(source, contains('lifetime_->store(false);'));
    expect(source, contains('mpv_render_context_set_update_callback'));
    expect(source, contains('unregistered_future.wait();'));
    expect(source, contains('texture_variants_.erase(old_texture_id);'));
  });
}
