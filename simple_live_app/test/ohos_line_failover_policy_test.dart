import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_line_failover_policy.dart';

void main() {
  test('selects each backup CDN once in circular order', () {
    expect(
      selectNextOhosFailoverLine(
        currentLineIndex: 0,
        lineCount: 3,
        failedLineIndices: {0},
      ),
      1,
    );
    expect(
      selectNextOhosFailoverLine(
        currentLineIndex: 1,
        lineCount: 3,
        failedLineIndices: {0, 1},
      ),
      2,
    );
    expect(
      selectNextOhosFailoverLine(
        currentLineIndex: 2,
        lineCount: 3,
        failedLineIndices: {0, 1, 2},
      ),
      isNull,
    );
  });

  test('does not fail over when the current line is invalid or alone', () {
    expect(
      selectNextOhosFailoverLine(
        currentLineIndex: -1,
        lineCount: 3,
        failedLineIndices: const {},
      ),
      isNull,
    );
    expect(
      selectNextOhosFailoverLine(
        currentLineIndex: 0,
        lineCount: 1,
        failedLineIndices: const {},
      ),
      isNull,
    );
  });
}
