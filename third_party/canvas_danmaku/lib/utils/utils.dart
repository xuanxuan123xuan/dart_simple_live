import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '/models/danmaku_content_item.dart';

class PreparedDanmakuLayout {
  final Size size;
  final ui.Paragraph paragraph;
  final ui.Paragraph? strokeParagraph;

  const PreparedDanmakuLayout({
    required this.size,
    required this.paragraph,
    this.strokeParagraph,
  });
}

class Utils {
  static final RegExp _emojiTokenPattern = RegExp(r'\[[^\[\]\r\n]{1,64}\]');
  static const double _singleLineLayoutWidth = 1000000;
  static const double _strokeOverflow = 2;

  static String normalizeImageUrl(String url) {
    final value = url.trim();
    if (value.startsWith("asset://")) {
      return value;
    }
    if (value.startsWith("//")) {
      return "https:$value";
    }
    return value;
  }

  static Size measureContent(
    DanmakuContentItem content,
    double fontSize,
    int fontWeight, [
    double emojiScale = 1.25,
    String? fontFamily,
  ]) {
    return prepareContent(
      content,
      fontSize,
      fontWeight,
      emojiScale,
      fontFamily,
      false,
    ).size;
  }

  static PreparedDanmakuLayout prepareContent(
    DanmakuContentItem content,
    double fontSize,
    int fontWeight, [
    double emojiScale = 1.25,
    String? fontFamily,
    bool showStroke = true,
  ]) {
    final paragraph = _buildParagraph(
      content,
      fontSize,
      fontWeight,
      emojiScale,
      fontFamily,
    );
    final contentWidth = max(
      paragraph.longestLine,
      paragraph.maxIntrinsicWidth,
    );
    final width = contentWidth.ceilToDouble() +
        (showStroke ? _strokeOverflow : 0);
    final height = paragraph.height.ceilToDouble();
    return PreparedDanmakuLayout(
      size: Size(width, height),
      paragraph: paragraph,
      strokeParagraph: showStroke
          ? _buildParagraph(
              content,
              fontSize,
              fontWeight,
              emojiScale,
              fontFamily,
              stroke: true,
            )
          : null,
    );
  }

  static ui.Paragraph generateParagraph(
    DanmakuContentItem content,
    double danmakuWidth,
    double fontSize,
    int fontWeight, [
    double emojiScale = 1.25,
    String? fontFamily,
  ]) {
    return _buildParagraph(
      content,
      fontSize,
      fontWeight,
      emojiScale,
      fontFamily,
    );
  }

  static ui.Paragraph generateStrokeParagraph(
    DanmakuContentItem content,
    double danmakuWidth,
    double fontSize,
    int fontWeight, [
    double emojiScale = 1.25,
    String? fontFamily,
  ]) {
    return _buildParagraph(
      content,
      fontSize,
      fontWeight,
      emojiScale,
      fontFamily,
      stroke: true,
    );
  }

  static ui.Paragraph _buildParagraph(
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    double emojiScale,
    String? fontFamily, {
    bool stroke = false,
  }) {
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
        fontWeight: FontWeight.values[fontWeight],
        fontFamily: fontFamily,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      ),
    )..pushStyle(
        ui.TextStyle(
          color: stroke ? null : content.color,
          foreground: stroke ? strokePaint : null,
          fontFamily: fontFamily,
        ),
      );
    _appendContent(
      builder,
      content,
      fontSize,
      fontWeight,
      emojiScale,
      fontFamily,
    );
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: _singleLineLayoutWidth));
  }

  static void drawEmojiImages(
    Canvas canvas,
    ui.Paragraph paragraph,
    DanmakuContentItem content,
    Offset offset,
    Map<String, ui.Image> imageCache,
    double fontSize,
    int fontWeight,
    double emojiScale,
    String? fontFamily,
  ) {
    final imageParts = contentParts(
      content,
    ).where((part) => part.isImage).toList(growable: false);
    if (imageParts.isEmpty) {
      return;
    }
    final boxes = paragraph.getBoxesForPlaceholders();
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final imageSize = fontSize * emojiScale;
    for (var i = 0; i < imageParts.length && i < boxes.length; i++) {
      final part = imageParts[i];
      final image = imageCache[normalizeImageUrl(part.imageUrl ?? '')];
      final box = boxes[i];
      if (image == null) {
        final fallbackText = part.fallbackText ?? '';
        if (fallbackText.isNotEmpty) {
          var fallbackPainter = TextPainter(
            text: TextSpan(
              text: fallbackText,
              style: TextStyle(
                color: content.color,
                fontSize: fontSize,
                fontWeight: FontWeight.values[fontWeight],
                fontFamily: fontFamily,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final availableWidth = box.right - box.left;
          if (fallbackPainter.width > availableWidth) {
            final fittedFontSize =
                fontSize * availableWidth / fallbackPainter.width;
            fallbackPainter = TextPainter(
              text: TextSpan(
                text: fallbackText,
                style: TextStyle(
                  color: content.color,
                  fontSize: fittedFontSize,
                  fontWeight: FontWeight.values[fontWeight],
                  fontFamily: fontFamily,
                ),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout();
          }
          fallbackPainter.paint(
            canvas,
            Offset(
              offset.dx +
                  box.left +
                  (box.right - box.left - fallbackPainter.width) / 2,
              offset.dy +
                  box.top +
                  (box.bottom - box.top - fallbackPainter.height) / 2,
            ),
          );
        }
        continue;
      }
      final drawSize = min(imageSize, box.bottom - box.top);
      final dst = Rect.fromLTWH(
        offset.dx + box.left + (box.right - box.left - drawSize) / 2,
        offset.dy + box.top + (box.bottom - box.top - drawSize) / 2,
        drawSize,
        drawSize,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst,
        paint,
      );
    }
  }

  static List<DanmakuContentPart> contentParts(DanmakuContentItem content) {
    final parts = content.parts ?? const <DanmakuContentPart>[];
    if (parts.isNotEmpty) {
      return parts;
    }
    final imageUrls = (content.imageUrls ?? const <String>[])
        .where((url) => url.trim().isNotEmpty)
        .toList();
    if (imageUrls.isEmpty) {
      return [
        if (content.text.isNotEmpty) DanmakuContentPart.text(content.text),
      ];
    }

    final result = <DanmakuContentPart>[];
    var start = 0;
    var imageIndex = 0;
    for (final match in _emojiTokenPattern.allMatches(content.text)) {
      if (imageIndex >= imageUrls.length) {
        break;
      }
      if (match.start > start) {
        result.add(
          DanmakuContentPart.text(content.text.substring(start, match.start)),
        );
      }
      result.add(
        DanmakuContentPart.image(
          imageUrls[imageIndex],
          fallbackText: match.group(0),
        ),
      );
      imageIndex += 1;
      start = match.end;
    }
    if (start < content.text.length) {
      result.add(DanmakuContentPart.text(content.text.substring(start)));
    }
    for (; imageIndex < imageUrls.length; imageIndex += 1) {
      result.add(DanmakuContentPart.image(imageUrls[imageIndex]));
    }
    return result;
  }

  static List<String> imageUrlsForContent(DanmakuContentItem content) {
    return contentParts(content)
        .where((part) => part.isImage)
        .map((part) => normalizeImageUrl(part.imageUrl ?? ""))
        .where((url) => url.isNotEmpty)
        .toList();
  }

  static void _appendContent(
    ui.ParagraphBuilder builder,
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    double emojiScale,
    String? fontFamily,
  ) {
    final imageSize = fontSize * emojiScale;
    for (final part in contentParts(content)) {
      if (part.isText) {
        builder.addText(part.text ?? "");
      } else if (part.isImage && (part.imageUrl ?? "").trim().isNotEmpty) {
        builder.addPlaceholder(
          imageSize,
          imageSize,
          ui.PlaceholderAlignment.middle,
        );
      }
    }
  }
}
