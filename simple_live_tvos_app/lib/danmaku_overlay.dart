import 'package:flutter/material.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DanmakuEvent {
  const DanmakuEvent(this.id, this.message, this.lane);
  final int id;
  final LiveMessage message;
  final int lane;
}

/// Animated text-only overlay. Emoji/image spans can be added later without
/// depending on Android's canvas_danmaku native/platform integrations.
class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({super.key, required this.events});
  final List<DanmakuEvent> events;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(
          builder: (context, box) {
            final lanes = (box.maxHeight / 58).floor().clamp(1, 10).toInt();
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final item in events)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: ((item.lane % lanes) * 58).toDouble(),
                    height: 48,
                    child: _FlyingComment(key: ValueKey(item.id), event: item),
                  ),
              ],
            );
          },
        ),
      );
}

class _FlyingComment extends StatefulWidget {
  const _FlyingComment({super.key, required this.event});
  final DanmakuEvent event;
  @override
  State<_FlyingComment> createState() => _FlyingCommentState();
}

class _FlyingCommentState extends State<_FlyingComment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..forward();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, box) {
          final text = '${widget.event.message.userName}: '
              '${widget.event.message.message}';
          final message = widget.event.message;
          final color = Color.fromARGB(
            255,
            message.color.r,
            message.color.g,
            message.color.b,
          );
          final approxWidth =
              (text.runes.length * 25.0).clamp(240.0, 1300.0).toDouble();
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                (box.maxWidth + approxWidth) * (1 - _controller.value) -
                    approxWidth,
                0,
              ),
              child: child,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  color: color,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      offset: Offset(1, 2),
                      blurRadius: 5,
                    ),
                    Shadow(color: Colors.black, blurRadius: 10),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
