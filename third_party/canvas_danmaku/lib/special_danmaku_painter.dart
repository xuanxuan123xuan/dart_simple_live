import 'dart:math';
import 'dart:ui' as ui;

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:canvas_danmaku/models/danmaku_item.dart';
import 'package:flutter/material.dart';

class SpecialDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> specialDanmakuItems;
  final double fontSize;
  final int fontWeight;
  final String? fontFamily;
  final bool running;
  final int tick;
  final int batchThreshold;

  SpecialDanmakuPainter(
    this.progress,
    this.specialDanmakuItems,
    this.fontSize,
    this.fontWeight,
    this.fontFamily,
    this.running,
    this.tick, {
    this.batchThreshold = 10, // 默认值为10，可以自行调整
  });

  @override
  void paint(Canvas canvas, Size size) {
    var pictureCanvas = canvas;
    var batch = specialDanmakuItems.length > batchThreshold;
    late ui.PictureRecorder pictureRecorder;
    if (batch) {
      pictureRecorder = ui.PictureRecorder();
      pictureCanvas = Canvas(pictureRecorder);
    }
    for (final item in specialDanmakuItems) {
      final elapsed = tick - item.creationTime;
      final content = item.content as SpecialDanmakuContentItem;
      if (elapsed >= 0 && elapsed < content.duration) {
        _paintSpecialDanmaku(pictureCanvas, content, size, elapsed);
      }
    }
    if (batch) {
      canvas.drawPicture(pictureRecorder.endRecording());
    }
  }

  void _paintSpecialDanmaku(
    Canvas canvas,
    SpecialDanmakuContentItem item,
    Size size,
    int elapsed,
  ) {
    // 透明度动画
    final state = placementFor(item, size, elapsed);
    if (state == null) return;
    final alpha = state.opacity;
    final color = item.alphaTween == null
        ? item.color
        : item.color.withValues(alpha: alpha);
    // 文本
    if (color != item.painterCache?.text?.style?.color) {
      item.painterCache!.text = TextSpan(
        text: item.text,
        style: TextStyle(
          color: color,
          fontSize: item.fontSize,
          fontWeight: FontWeight.values[fontWeight],
          fontFamily: fontFamily,
          shadows: item.hasStroke
              ? [
                  Shadow(
                    color: Colors.black.withValues(alpha: alpha),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
      );
      item.painterCache!.layout();
    }

    // 路径动画 TODO

    if (item.matrix != null) {
      canvas.save();
      canvas.translate(state.offset.dx, state.offset.dy);
      canvas.transform(item.matrix!.storage);
      item.painterCache!.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      item.painterCache!.paint(canvas, state.offset);
    }
  }

  /// Returns the translation and alpha used to paint a special item at an
  /// elapsed renderer time. The recording observer shares this calculation so
  /// replay placement stays aligned with the live painter.
  static SpecialDanmakuPlacement? placementFor(
    SpecialDanmakuContentItem item,
    Size size,
    int elapsed,
  ) {
    if (elapsed < 0 || elapsed >= item.duration) return null;
    final alpha =
        item.alphaTween?.transform(elapsed / item.duration) ?? item.color.a;

    late double dx;
    late double dy;
    if (elapsed > item.translationStartDelay) {
      final translateProgress = item.easingType.transform(
        min(
          1.0,
          (elapsed - item.translationStartDelay) / item.translationDuration,
        ),
      );

      double getOffset(Tween<double> tween) => tween is ConstantTween
          ? tween.begin!
          : tween.transform(translateProgress);

      dx = getOffset(item.translateXTween) * size.width;
      dy = getOffset(item.translateYTween) * size.height;
    } else {
      dx = item.translateXTween.begin! * size.width;
      dy = item.translateYTween.begin! * size.height;
    }

    return SpecialDanmakuPlacement(
      offset: Offset(dx, dy),
      opacity: alpha,
      transform: item.matrix?.storage.toList(growable: false),
    );
  }

  @override
  bool shouldRepaint(covariant SpecialDanmakuPainter oldDelegate) {
    return true;
  }
}

class SpecialDanmakuPlacement {
  const SpecialDanmakuPlacement({
    required this.offset,
    required this.opacity,
    required this.transform,
  });

  final Offset offset;
  final double opacity;
  final List<double>? transform;
}
