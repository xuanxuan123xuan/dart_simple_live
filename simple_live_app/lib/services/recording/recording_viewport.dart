import 'package:flutter/painting.dart';

/// Full source-video rectangle in danmaku-local coordinates. For cover, this
/// deliberately extends outside the viewport so cropped source edges stay empty.
Rect recordingVideoRect({
  required Size source,
  required Size viewport,
  required BoxFit fit,
  Alignment alignment = Alignment.center,
  Offset danmakuOrigin = Offset.zero,
}) {
  if (source.isEmpty || viewport.isEmpty) return Offset.zero & viewport;
  final fitted = applyBoxFit(fit, source, viewport);
  final full = Size(
      source.width * fitted.destination.width / fitted.source.width,
      source.height * fitted.destination.height / fitted.source.height);
  return alignment.inscribe(full, Offset.zero & viewport).shift(-danmakuOrigin);
}
