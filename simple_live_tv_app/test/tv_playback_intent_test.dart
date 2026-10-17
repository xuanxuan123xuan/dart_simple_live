import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_playback_intent.dart';

void main() {
  test('background and focus recovery cannot undo a manual pause', () {
    final intent = TvPlaybackIntent();
    intent.suspend(TvPlaybackSuspension.background);
    intent.suspend(TvPlaybackSuspension.focus);
    intent.userPaused = true;
    intent.resume(TvPlaybackSuspension.background);
    expect(intent.shouldPlay, isFalse);
    intent.resume(TvPlaybackSuspension.focus);
    expect(intent.shouldPlay, isFalse);
    intent.userPaused = false;
    expect(intent.shouldPlay, isTrue);
  });

  test('closing a session permanently rejects late recovery', () {
    final intent = TvPlaybackIntent()..close();
    intent.userPaused = false;
    intent.resume(TvPlaybackSuspension.resources);
    expect(intent.shouldPlay, isFalse);
  });
}
