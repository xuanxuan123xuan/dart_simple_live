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

    final matches = _emojiTokenPattern
        .allMatches(content.text)
        .toList(growable: false);
    final (tokenUrls, consumedUrls) = _pairTokensWithUrls(matches, imageUrls);

    final result = <DanmakuContentPart>[];
    var start = 0;
    for (var i = 0; i < matches.length; i++) {
      final url = tokenUrls[i];
      if (url == null) {
        // 没有地址可配对，token 原文留在待输出的文本区间里，避免丢字
        continue;
      }
      final match = matches[i];
      if (match.start > start) {
        result.add(
          DanmakuContentPart.text(content.text.substring(start, match.start)),
        );
      }
      result.add(
        DanmakuContentPart.image(url, fallbackText: match.group(0)),
      );
      start = match.end;
    }
    if (start < content.text.length) {
      result.add(DanmakuContentPart.text(content.text.substring(start)));
    }
    // 有些站点会给出文本里没有对应 token 的图片，剩余地址仍追加到末尾
    for (var i = consumedUrls; i < imageUrls.length; i++) {
      result.add(DanmakuContentPart.image(imageUrls[i]));
    }
    return result;
  }

  /// 把文本里的表情 token 与 [imageUrls] 配对，返回每个 token 的地址
  /// （配不上时为 null）以及已消耗的地址数量。
  ///
  /// 各站点的 imageUrls 都是 `.toSet().toList()` 去重后的结果，重复表情只剩一个
  /// 地址，按下标逐个配对会让第二次及以后的重复 token 退化成字面量文本。
  /// 所以 token 数超过地址数时几乎必然是被去重过：改为按「首次出现顺序」给去重后
  /// 的 token 分配地址，同一 token 的每次出现复用同一地址，正好抵消上游的去重。
  static (List<String?>, int) _pairTokensWithUrls(
    List<RegExpMatch> matches,
    List<String> imageUrls,
  ) {
    if (matches.length <= imageUrls.length) {
      // 数量本就对得上，说明没被去重影响，保持原有的按位配对
      return (
        List<String?>.generate(matches.length, (index) => imageUrls[index]),
        matches.length,
      );
    }
    final urlByToken = <String, String>{};
    for (final match in matches) {
      final token = match.group(0)!;
      if (urlByToken.containsKey(token)) {
        continue;
      }
      if (urlByToken.length >= imageUrls.length) {
        break;
      }
      urlByToken[token] = imageUrls[urlByToken.length];
    }
    return (
      matches
          .map((match) => urlByToken[match.group(0)!])
          .toList(growable: false),
      urlByToken.length,
    );
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
