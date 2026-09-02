import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

void main() {
  test('candidate lines stay within the active protocol family', () {
    expect(
      resolveOhosAutoLineCandidateIndices(
        urls: const [
          'https://cdn.example/live.flv',
          'https://backup.example/live.flv',
          'https://cdn.example/live.m3u8',
          'rtmp://legacy.example/live',
        ],
        currentLineIndex: 0,
      ),
      [0, 1],
    );
  });

  test('invalid active line has no candidates', () {
    expect(
      resolveOhosAutoLineCandidateIndices(
        urls: const ['https://cdn.example/live.flv'],
        currentLineIndex: -1,
      ),
      isEmpty,
    );
  });

  test('selection result is rejected after any captured identity changes', () {
    final base = <String, Object>{
      'roomGeneration': 4,
      'expectedRoomGeneration': 4,
      'playbackRequestRevision': 7,
      'latestPlaybackRequestRevision': 7,
      'playerGeneration': 11,
      'currentPlayerGeneration': 11,
      'manualLineSelectionRevision': 2,
      'latestManualLineSelectionRevision': 2,
      'hasActivePlaybackSession': true,
      'playerRecovering': false,
      'autoLineSwitchAlreadyCompleted': false,
    };

    bool evaluate(Map<String, Object> values) {
      return shouldAcceptOhosAutoLineSelection(
        roomGeneration: values['roomGeneration']! as int,
        expectedRoomGeneration: values['expectedRoomGeneration']! as int,
        playbackRequestRevision: values['playbackRequestRevision']! as int,
        latestPlaybackRequestRevision:
            values['latestPlaybackRequestRevision']! as int,
        playerGeneration: values['playerGeneration']! as int,
        currentPlayerGeneration: values['currentPlayerGeneration']! as int,
        manualLineSelectionRevision:
            values['manualLineSelectionRevision']! as int,
        latestManualLineSelectionRevision:
            values['latestManualLineSelectionRevision']! as int,
        hasActivePlaybackSession: values['hasActivePlaybackSession']! as bool,
        playerRecovering: values['playerRecovering']! as bool,
        autoLineSwitchAlreadyCompleted:
            values['autoLineSwitchAlreadyCompleted']! as bool,
      );
    }

    expect(evaluate(base), isTrue);
    for (final key in [
      'expectedRoomGeneration',
      'latestPlaybackRequestRevision',
      'currentPlayerGeneration',
      'latestManualLineSelectionRevision',
    ]) {
      final changed = Map<String, Object>.of(base);
      changed[key] = (changed[key]! as int) + 1;
      expect(evaluate(changed), isFalse, reason: key);
    }

    final userOperation = Map<String, Object>.of(base)
      ..['playerRecovering'] = true;
    expect(evaluate(userOperation), isFalse);

    final completed = Map<String, Object>.of(base)
      ..['autoLineSwitchAlreadyCompleted'] = true;
    expect(evaluate(completed), isFalse);
  });
}
