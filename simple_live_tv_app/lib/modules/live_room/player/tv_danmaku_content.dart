import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Builds the canvas payload for one chat message.
///
/// Single-room and multi-room canvases share this conversion so emoji images,
/// the original text/image order and the fallback text all survive the hop into
/// `canvas_danmaku`.
///
/// When [renderEmoji] is off no image data is passed at all, keeping the
/// existing meaning of the setting. When the message carries no usable span
/// data the legacy [LiveMessage.imageUrls] list is forwarded instead.
DanmakuContentItem buildTvDanmakuContent(
  LiveMessage message, {
  required bool renderEmoji,
}) {
  final parts = renderEmoji ? buildTvDanmakuContentParts(message.spans) : null;
  return DanmakuContentItem(
    message.message,
    color: Color.fromARGB(
      255,
      message.color.r,
      message.color.g,
      message.color.b,
    ),
    imageUrls: renderEmoji && parts == null ? message.imageUrls : null,
    parts: parts,
  );
}

/// Converts [LiveMessageSpan]s into ordered text/image parts.
///
/// Returns null when there is nothing to draw so callers can fall back to
/// [LiveMessage.imageUrls]. Repeated emoji urls are kept as-is; the canvas
/// caches decoded images by url.
List<DanmakuContentPart>? buildTvDanmakuContentParts(
  List<LiveMessageSpan>? spans,
) {
  final source = spans ?? const <LiveMessageSpan>[];
  if (source.isEmpty) {
    return null;
  }
  final parts = <DanmakuContentPart>[];
  for (final span in source) {
    if (span.isText) {
      final text = span.text ?? "";
      if (text.isNotEmpty) {
        parts.add(DanmakuContentPart.text(text));
      }
    } else if (span.isImage) {
      final imageUrl = (span.imageUrl ?? "").trim();
      if (imageUrl.isNotEmpty) {
        parts.add(
          DanmakuContentPart.image(
            imageUrl,
            fallbackText: span.fallbackText,
          ),
        );
      }
    } else {
      // An image span without a usable url would otherwise vanish; keep its
      // fallback text so the viewer still sees the original emoji label.
      final fallbackText = (span.fallbackText ?? "").trim();
      if (fallbackText.isNotEmpty) {
        parts.add(DanmakuContentPart.text(fallbackText));
      }
    }
  }
  return parts.isEmpty ? null : parts;
}
