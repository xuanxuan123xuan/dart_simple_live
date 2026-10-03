import 'dart:math' as math;

import 'package:flutter/widgets.dart';

Rect resolveLiveRoomHoldPreviewRect({
  required Size screenSize,
  required EdgeInsets safePadding,
  required Rect playerRect,
  required bool portrait,
  double obscuredRight = 0,
}) {
  const margin = 12.0;
  final safeRect = Rect.fromLTRB(
    safePadding.left,
    safePadding.top,
    screenSize.width - safePadding.right,
    screenSize.height - safePadding.bottom,
  );
  var available = playerRect.intersect(safeRect);
  if (available.isEmpty) {
    available = safeRect;
  }
  if (obscuredRight > 0) {
    available = Rect.fromLTRB(
      available.left,
      available.top,
      math.max(available.left, available.right - obscuredRight),
      available.bottom,
    );
  }

  final maxWidth = math.max(
    0.0,
    math.min(
      available.width - margin * 2,
      available.height * 16 / 9,
    ),
  );
  final requestedWidth = portrait
      ? (available.width * 0.62).clamp(200.0, 320.0).toDouble()
      : (available.width * 0.30).clamp(260.0, 420.0).toDouble();
  final width = math.min(requestedWidth, maxWidth);
  final height = width * 9 / 16;
  final top = math.min(
    available.top + margin,
    math.max(available.top, available.bottom - height),
  );
  final left = portrait
      ? available.left + (available.width - width) / 2
      : available.right - margin - width;
  return Rect.fromLTWH(
    left
        .clamp(
          available.left,
          math.max(available.left, available.right - width),
        )
        .toDouble(),
    top,
    width,
    height,
  );
}
