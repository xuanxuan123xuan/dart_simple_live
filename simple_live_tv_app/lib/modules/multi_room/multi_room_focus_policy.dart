import 'package:flutter/services.dart';

/// Directional focus rules for the numbered multi-room grid.
class MultiRoomFocusPolicy {
  const MultiRoomFocusPolicy._();

  static int? nextGridIndex({
    required int currentIndex,
    required int roomCount,
    required int columnCount,
    required LogicalKeyboardKey key,
  }) {
    if (roomCount <= 0 ||
        columnCount <= 0 ||
        currentIndex < 0 ||
        currentIndex >= roomCount) {
      return null;
    }
    final row = currentIndex ~/ columnCount;
    final column = currentIndex % columnCount;
    final target = switch (key) {
      LogicalKeyboardKey.arrowLeft when column > 0 => currentIndex - 1,
      LogicalKeyboardKey.arrowRight
          when column < columnCount - 1 && currentIndex + 1 < roomCount =>
        currentIndex + 1,
      LogicalKeyboardKey.arrowUp when row > 0 => currentIndex - columnCount,
      LogicalKeyboardKey.arrowDown
          when currentIndex + columnCount < roomCount =>
        currentIndex + columnCount,
      _ => null,
    };
    return target;
  }
}

bool isRoomSuspendedByFocus({
  required String roomKey,
  required String? activeRoomKey,
}) {
  return activeRoomKey != null && roomKey != activeRoomKey;
}
