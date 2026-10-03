import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';

export 'live_room_hold_preview_layout.dart';

enum LiveRoomHoldPreviewPhase {
  holding,
  lingering,
  switching,
  loadingPrevious,
  closed,
}

class LiveRoomHoldPreviewOverlay extends StatelessWidget {
  const LiveRoomHoldPreviewOverlay({
    super.key,
    required this.rect,
    required this.item,
    required this.phase,
    required this.playerController,
    required this.lingerDeadline,
    required this.onTap,
    this.onPhysicalSizeChanged,
  });

  final Rect rect;
  final MultiRoomItem item;
  final LiveRoomHoldPreviewPhase phase;
  final MultiRoomPlayerController? playerController;
  final DateTime? lingerDeadline;
  final VoidCallback onTap;
  final void Function(double width, double height)? onPhysicalSizeChanged;

  bool get _interactive => phase == LiveRoomHoldPreviewPhase.lingering;

  @override
  Widget build(BuildContext context) {
    final controller = playerController;
    final remaining = lingerDeadline == null
        ? Duration.zero
        : lingerDeadline!.difference(DateTime.now());
    final countdownDuration = remaining.isNegative ? Duration.zero : remaining;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onPhysicalSizeChanged?.call(
        rect.width * pixelRatio,
        rect.height * pixelRatio,
      );
    });

    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        ignoring: !_interactive,
        child: Material(
          color: Colors.black,
          elevation: 14,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _interactive ? onTap : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null)
                  ObxPreviewPlayer(controller: controller)
                else
                  const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.site.name} · ${item.userName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (phase == LiveRoomHoldPreviewPhase.switching)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          else if (_interactive)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Text(
                                '点击切换',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_interactive && countdownDuration > Duration.zero)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(lingerDeadline),
                      tween: Tween(begin: 1, end: 0),
                      duration: countdownDuration,
                      builder: (_, value, __) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: value,
                          child: Container(
                            height: 3,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ObxPreviewPlayer extends StatelessWidget {
  const ObxPreviewPlayer({super.key, required this.controller});

  final MultiRoomPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final error = controller.errorText.value.trim();
        if (error.isNotEmpty) {
          return const Center(
            child: Text(
              '预览失败',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          );
        }
        if (!controller.loading.value && !controller.liveStatus.value) {
          return const Center(
            child: Text(
              '主播已下播',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: controller.videoController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              wakelock: false,
              pauseUponEnteringBackgroundMode: true,
              resumeUponEnteringForegroundMode: false,
            ),
            if (controller.loading.value)
              const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        );
      },
    );
  }
}
