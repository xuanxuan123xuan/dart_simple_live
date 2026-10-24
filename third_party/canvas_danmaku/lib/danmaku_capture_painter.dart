import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'danmaku_capture.dart';
import 'models/danmaku_content_item.dart';
import 'models/danmaku_item.dart';
import 'special_danmaku_painter.dart';
import 'utils/utils.dart';

/// Observes the three live painter layers after they have updated their item
/// positions. It draws nothing and has no work while capture is disabled.
class DanmakuCapturePainter extends CustomPainter {
  DanmakuCapturePainter({
    required Listenable repaint,
    required this.scrollItems,
    required this.topItems,
    required this.bottomItems,
    required this.specialItems,
    required this.controller,
    required this.tick,
    required this.fontSize,
    required this.fontWeight,
    required this.fontFamily,
    required this.emojiScale,
    required this.showStroke,
    required this.opacity,
    required this.emojiImageCache,
  }) : super(repaint: repaint);

  final List<DanmakuItem> scrollItems;
  final List<DanmakuItem> topItems;
  final List<DanmakuItem> bottomItems;
  final List<DanmakuItem> specialItems;
  final DanmakuCaptureController? controller;
  final int Function() tick;
  final double fontSize;
  final int fontWeight;
  final String? fontFamily;
  final double emojiScale;
  final bool showStroke;
  final double opacity;
  final Map<String, ui.Image> emojiImageCache;

  static const double _spritePadding = 4;
  static const _maxSpritePixels = 16 * 1024 * 1024;
  static const _maxInFlightBytes = 64 * 1024 * 1024;
  static int _inFlightBytes = 0;
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.green;

  @override
  void paint(Canvas canvas, Size size) {
    final captureController = controller;
    if (captureController == null || !captureController.enabled) return;

    final sources = <DanmakuCaptureSource>[];
    final rendererTick = tick();
    for (final item in scrollItems) {
      if (item.xPosition + item.width < 0 || item.xPosition > size.width) {
        continue;
      }
      sources.add(
        _ordinarySource(
          item,
          item.xPosition,
          item.yPosition,
        ),
      );
    }
    for (final item in topItems) {
      sources.add(
        _ordinarySource(item, item.xPosition, item.yPosition),
      );
    }
    for (final item in bottomItems) {
      sources.add(
        _ordinarySource(
          item,
          item.xPosition,
          size.height - item.yPosition - item.height,
        ),
      );
    }
    for (final item in specialItems) {
      final special = item.content as SpecialDanmakuContentItem;
      final state = SpecialDanmakuPainter.placementFor(
        special,
        size,
        rendererTick - item.creationTime,
      );
      if (state == null) continue;
      sources.add(_specialSource(special, state));
    }

    captureController.capture(
      rendererTickMilliseconds: rendererTick,
      viewportSize: size,
      opacity: opacity,
      sources: sources,
    );
  }

  DanmakuCaptureSource _ordinarySource(
    DanmakuItem item,
    double x,
    double y,
  ) {
    final content = item.content;
    final imageSignature = Utils.imageUrlsForContent(content)
        .map((url) => emojiImageCache[url] == null
            ? 0
            : identityHashCode(emojiImageCache[url]))
        .toList(growable: false);
    final partsSignature = Utils.contentParts(content)
        .map((part) => part.isText
            ? ['text', part.text]
            : [
                'image',
                Utils.normalizeImageUrl(part.imageUrl ?? ''),
                part.fallbackText,
              ])
        .toList(growable: false);
    final visualKey = jsonEncode([
      content.text,
      content.color.toARGB32(),
      content.selfSend,
      partsSignature,
      imageSignature,
      fontSize,
      fontWeight,
      fontFamily,
      emojiScale,
      showStroke,
    ]);
    final spriteWidth = (item.width + _spritePadding * 2).ceil();
    final spriteHeight = (item.height + _spritePadding * 2).ceil();

    return DanmakuCaptureSource(
      visualKey: visualKey,
      x: x - _spritePadding,
      y: y - _spritePadding,
      width: spriteWidth.toDouble(),
      height: spriteHeight.toDouble(),
      opacity: 1,
      renderPng: () => _renderPng(spriteWidth, spriteHeight, (canvas) {
        final paragraph = item.paragraph ??
            Utils.generateParagraph(
              content,
              item.width,
              fontSize,
              fontWeight,
              emojiScale,
              fontFamily,
            );
        if (showStroke) {
          final strokeParagraph = item.strokeParagraph ??
              Utils.generateStrokeParagraph(
                content,
                item.width,
                fontSize,
                fontWeight,
                emojiScale,
                fontFamily,
              );
          canvas.drawParagraph(
            strokeParagraph,
            const Offset(_spritePadding, _spritePadding),
          );
        }
        if (content.selfSend) {
          canvas.drawRect(
            Offset(_spritePadding, _spritePadding).translate(-2, 2) &
                (Size(item.width, item.height) + const Offset(4, 0)),
            _selfSendPaint,
          );
        }
        const textOffset = Offset(_spritePadding, _spritePadding);
        canvas.drawParagraph(paragraph, textOffset);
        Utils.drawEmojiImages(
          canvas,
          paragraph,
          content,
          textOffset,
          emojiImageCache,
          fontSize,
          fontWeight,
          emojiScale,
          fontFamily,
        );
      }),
    );
  }

  DanmakuCaptureSource _specialSource(
    SpecialDanmakuContentItem item,
    SpecialDanmakuPlacement state,
  ) {
    final visualKey = jsonEncode([
      'special',
      item.text,
      item.color.toARGB32(),
      item.fontSize,
      item.hasStroke,
      fontWeight,
      fontFamily,
    ]);
    final painter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          color: item.color.withValues(alpha: 1),
          fontSize: item.fontSize,
          fontWeight: FontWeight.values[fontWeight],
          fontFamily: fontFamily,
          shadows: item.hasStroke
              ? [
                  Shadow(
                    color: Colors.black.withValues(alpha: 1),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final spriteWidth = (painter.width + _spritePadding * 2).ceil();
    final spriteHeight = (painter.height + _spritePadding * 2).ceil();

    return DanmakuCaptureSource(
      visualKey: visualKey,
      x: state.offset.dx - _spritePadding,
      y: state.offset.dy - _spritePadding,
      width: spriteWidth.toDouble(),
      height: spriteHeight.toDouble(),
      opacity: state.opacity,
      transform: state.transform,
      transformOriginX: _spritePadding,
      transformOriginY: _spritePadding,
      dispose: painter.dispose,
      renderPng: () => _renderPng(spriteWidth, spriteHeight, (canvas) {
        painter.paint(canvas, const Offset(_spritePadding, _spritePadding));
      }),
    );
  }

  static Future<Uint8List> _renderPng(
    int width,
    int height,
    void Function(Canvas canvas) paint, {
    Future<ui.Image> Function(ui.Picture picture, int width, int height)?
        rasterize,
  }) async {
    if (width <= 0 ||
        height <= 0 ||
        width > _maxSpritePixels ||
        height > _maxSpritePixels ||
        width * height > _maxSpritePixels) {
      throw StateError(
          'Danmaku capture sprite dimensions exceed the 16M-pixel limit.');
    }
    // Reserve for both the RGBA image and its encoding/readback workspace.
    // Keep the reservation until the image and picture have both been disposed.
    final bytes = width * height * 8;
    if (_inFlightBytes + bytes > _maxInFlightBytes) {
      throw StateError(
          'Danmaku capture exceeded its 64MiB raster memory budget.');
    }
    _inFlightBytes += bytes;
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    ui.Image? image;
    try {
      recorder = ui.PictureRecorder();
      paint(Canvas(recorder));
      picture = recorder.endRecording();
      image = await (rasterize?.call(picture, width, height) ??
          picture.toImage(width, height));
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Could not encode a danmaku capture sprite as PNG.');
      }
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } finally {
      try {
        image?.dispose();
        picture?.dispose();
        if (recorder?.isRecording ?? false) recorder!.endRecording().dispose();
      } finally {
        _inFlightBytes -= bytes;
      }
    }
  }

  @visibleForTesting
  static Future<Uint8List> renderPngForTesting(
          int width, int height, void Function(Canvas canvas) paint,
          {Future<ui.Image> Function(ui.Picture picture, int width, int height)?
              rasterize}) =>
      _renderPng(width, height, paint, rasterize: rasterize);

  @override
  bool shouldRepaint(covariant DanmakuCapturePainter oldDelegate) => true;
}
