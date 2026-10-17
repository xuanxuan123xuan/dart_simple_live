import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

/// Focusable TV controls, kept independent of the native player for key tests.
class TvPlayerControlBar extends StatefulWidget {
  const TvPlayerControlBar({
    super.key,
    required this.paused,
    required this.muted,
    required this.volume,
    required this.onTogglePause,
    required this.onToggleMute,
    required this.onVolumeDown,
    required this.onVolumeUp,
    required this.onPrevious,
    required this.onNext,
    required this.onRefresh,
    required this.onSettings,
    required this.onActivity,
    this.onMultiRoom,
  });

  final bool paused;
  final bool muted;
  final double volume;
  final VoidCallback onTogglePause;
  final VoidCallback onToggleMute;
  final VoidCallback onVolumeDown;
  final VoidCallback onVolumeUp;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback onActivity;
  final VoidCallback? onMultiRoom;

  @override
  State<TvPlayerControlBar> createState() => _TvPlayerControlBarState();
}

class _TvPlayerControlBarState extends State<TvPlayerControlBar> {
  final _nodes = List.generate(9, (_) => AppFocusNode());

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(String, IconData, VoidCallback)>[
      (
        widget.paused ? '继续' : '暂停',
        widget.paused ? Icons.play_arrow : Icons.pause,
        widget.onTogglePause
      ),
      (
        widget.muted ? '恢复声音' : '静音',
        widget.muted ? Icons.volume_off : Icons.volume_up,
        widget.onToggleMute
      ),
      ('音量 −', Icons.remove, widget.onVolumeDown),
      ('音量 +', Icons.add, widget.onVolumeUp),
      ('上一频道', Icons.skip_previous, widget.onPrevious),
      ('下一频道', Icons.skip_next, widget.onNext),
      ('刷新', Icons.refresh, widget.onRefresh),
      ('清晰度 / 线路', Icons.settings, widget.onSettings),
      if (widget.onMultiRoom != null)
        ('多屏', Icons.grid_view, widget.onMultiRoom!),
    ];
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            widget.onActivity();
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('音量：${widget.muted ? 0 : widget.volume.round()}',
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < actions.length; i++)
                  HighlightButton(
                    key: ValueKey('tv-player-action-$i'),
                    focusNode: _nodes[i],
                    autofocus: i == 0,
                    text: actions[i].$1,
                    iconData: actions[i].$2,
                    onTap: () {
                      widget.onActivity();
                      actions[i].$3();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
