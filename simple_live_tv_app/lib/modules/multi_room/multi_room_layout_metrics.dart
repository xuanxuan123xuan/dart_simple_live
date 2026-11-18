import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class TvMultiRoomLayoutMetrics {
  const TvMultiRoomLayoutMetrics({
    required this.tileSize,
    required this.contentSize,
  });

  final Size tileSize;
  final Size contentSize;

  static TvMultiRoomLayoutMetrics twoRoom({
    required Size viewport,
    required double gap,
    required bool mainSub,
  }) {
    final ratio = mainSub ? 2.0 : 1.0;
    final horizontalSpace = math.max(0.0, viewport.width - gap);
    final verticalSpace = math.max(0.0, viewport.height);
    final tileWidth = math.min(
      horizontalSpace / (ratio + 1),
      verticalSpace * 16 / 9 / ratio,
    );
    final tileHeight = tileWidth * 9 / 16;
    return TvMultiRoomLayoutMetrics(
      tileSize: Size(tileWidth, tileHeight),
      contentSize: Size(
        tileWidth * (ratio + 1) + gap,
        tileHeight * ratio,
      ),
    );
  }

  static TvMultiRoomLayoutMetrics grid({
    required Size viewport,
    required double gap,
  }) {
    final horizontalSpace = math.max(0.0, viewport.width - gap);
    final verticalSpace = math.max(0.0, viewport.height - gap);
    final tileWidth = math.min(
      horizontalSpace / 2,
      verticalSpace / 2 * 16 / 9,
    );
    final tileHeight = tileWidth * 9 / 16;
    return TvMultiRoomLayoutMetrics(
      tileSize: Size(tileWidth, tileHeight),
      contentSize: Size(tileWidth * 2 + gap, tileHeight * 2 + gap),
    );
  }
}
