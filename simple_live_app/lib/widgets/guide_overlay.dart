import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/guide_service.dart';

class GuideOverlay extends GetView<GuideService> {
  const GuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.overlayVisible.value || !controller.isActive) {
        return const SizedBox.shrink();
      }
      final flow = controller.activeFlow.value!;
      final step = flow.current;
      final rect = controller.focusRect.value ?? step.highlightRect;
      final size = MediaQuery.of(context).size;
      final bubblePosition = _resolveBubblePosition(size, rect);
      return Positioned.fill(
        child: Stack(
          key: controller.overlayKey,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: CustomPaint(
                  painter: _GuideMaskPainter(rect),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: bubblePosition.left,
              right: bubblePosition.right,
              top: bubblePosition.top,
              bottom: bubblePosition.bottom,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(step.kind),
                tween: Tween(begin: 0.96, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.topLeft,
                    child: child,
                  );
                },
                child: _GuideBubble(
                  title: step.title,
                  message: step.message,
                  onNext: controller.nextStep,
                  nextLabel: flow.hasNext ? '下一步' : '完成',
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  _GuideBubblePosition _resolveBubblePosition(Size size, Rect? rect) {
    if (rect == null) {
      return const _GuideBubblePosition(left: 16, right: 16, bottom: 24);
    }
    const bubbleWidth = 320.0;
    const estimatedBubbleHeight = 140.0;
    final useFullWidth = size.width < bubbleWidth + 32;
    final left = math.max(
      16.0,
      math.min(rect.left - 4, size.width - bubbleWidth - 16),
    );
    final top = rect.top < estimatedBubbleHeight + 40
        ? math.max(
            16.0,
            math.min(
                size.height - estimatedBubbleHeight - 16, rect.bottom + 12),
          )
        : math.max(16.0, rect.top - 12);
    return _GuideBubblePosition(
      left: useFullWidth ? 16 : left,
      right: useFullWidth ? 16 : null,
      top: top,
    );
  }
}

class _GuideBubblePosition {
  const _GuideBubblePosition({
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
}

class _GuideBubble extends StatelessWidget {
  const _GuideBubble({
    required this.title,
    required this.message,
    required this.onNext,
    required this.nextLabel,
  });

  final String title;
  final String message;
  final VoidCallback onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: AppStyle.radius12,
          boxShadow: const [
            BoxShadow(
              blurRadius: 24,
              offset: Offset(0, 8),
              color: Colors.black26,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onNext,
                child: Text(nextLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideMaskPainter extends CustomPainter {
  _GuideMaskPainter(this.rect);

  static const _highlightPadding = 6.0;
  static const _highlightRadius = Radius.circular(30);

  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withAlpha(153);
    final path = Path()..addRect(Offset.zero & size);
    if (rect != null) {
      path.addRRect(
        RRect.fromRectAndRadius(
          rect!.inflate(_highlightPadding),
          _highlightRadius,
        ),
      );
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, paint);
    if (rect != null) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect!.inflate(_highlightPadding),
          _highlightRadius,
        ),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuideMaskPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
