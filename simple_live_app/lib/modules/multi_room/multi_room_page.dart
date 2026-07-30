import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';

class MultiRoomPage extends GetView<MultiRoomController> {
  const MultiRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Obx(() => Text("多开同屏（${controller.rooms.length}）")),
        actions: [
          IconButton(
            tooltip: "全部刷新",
            onPressed: () {
              for (final room in controller.rooms) {
                controller.playerFor(room).refreshRoom();
              }
            },
            icon: const Icon(Remix.refresh_line),
          ),
        ],
      ),
      body: Obx(
        () => LayoutBuilder(
          builder: (context, constraints) {
            final rooms = controller.rooms.toList();
            if (rooms.isEmpty) {
              return const _CenterText("没有可播放的直播间");
            }
            final gap = AppSettingsController.instance
                .effectiveMultiRoomGap
                .toDouble();
            final columns = _bestColumnCount(
              rooms.length,
              constraints.maxWidth,
              constraints.maxHeight,
              gap,
            );
            final rows = (rooms.length / columns).ceil();
            return Padding(
              padding: EdgeInsets.all(gap),
              child: Column(
                children: [
                  for (var row = 0; row < rows; row += 1) ...[
                    if (row > 0) SizedBox(height: gap),
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < columns; col += 1) ...[
                            if (col > 0) SizedBox(width: gap),
                            Expanded(
                              child: _tileAt(row * columns + col, rooms),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tileAt(int index, List<MultiRoomItem> rooms) {
    // 最后一行可能不满，空位留空白占位以保持每格等宽。
    if (index >= rooms.length) {
      return const SizedBox.shrink();
    }
    final room = rooms[index];
    return _MultiRoomTile(
      item: room,
      controller: controller.playerFor(room),
      onRemove: () => controller.removeRoom(room),
    );
  }

  /// 选出让每格画面最大的列数。
  ///
  /// 画面按 16:9 等比缩放（不裁切），格子比例与之不符时会留黑边。因此逐个试列数，
  /// 算出该排法下画面实际能渲染多大，取最大者 —— 横屏放两个时它会自然选出
  /// 上下排（1 列），因为上下排每格更宽，画面比左右并排大约 50%。
  int _bestColumnCount(int length, double width, double height, double gap) {
    if (length <= 1 || width <= 0 || height <= 0) {
      return 1;
    }
    var bestColumns = 1;
    var bestArea = -1.0;
    for (var columns = 1; columns <= length; columns += 1) {
      final rows = (length / columns).ceil();
      final cellWidth = (width - gap * (columns - 1)) / columns;
      final cellHeight = (height - gap * (rows - 1)) / rows;
      if (cellWidth <= 0 || cellHeight <= 0) {
        continue;
      }
      // 画面按 contain 缩放后的实际尺寸。
      final videoWidth = cellWidth / cellHeight > 16 / 9
          ? cellHeight * 16 / 9
          : cellWidth;
      final videoHeight = videoWidth * 9 / 16;
      final area = videoWidth * videoHeight;
      if (area > bestArea) {
        bestArea = area;
        bestColumns = columns;
      }
    }
    return bestColumns;
  }
}

class _MultiRoomTile extends StatelessWidget {
  final MultiRoomItem item;
  final MultiRoomPlayerController controller;
  final VoidCallback onRemove;

  const _MultiRoomTile({
    required this.item,
    required this.controller,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppStyle.radius8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white24),
          borderRadius: AppStyle.radius8,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(
                controller: controller.videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
            // 弹幕铺在画面区域上。行数按格子高度自适应，格子太矮时会自动隐藏。
            Positioned.fill(
              child: Obx(
                () => controller.showDanmaku.value
                    ? _DanmakuLayer(controller: controller)
                    : const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: Obx(
                () {
                  if (controller.loading.value) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (controller.errorText.value.isNotEmpty) {
                    return _CenterText(controller.errorText.value);
                  }
                  if (!controller.liveStatus.value) {
                    return const _CenterText("未开播");
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: Colors.black.withAlpha(150),
                child: Obx(
                  () => Text(
                    "${item.site.name} · ${controller.title}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Obx(
                () => Text(
                  [
                    if (controller.qualityInfo.value.isNotEmpty)
                      controller.qualityInfo.value,
                    if (controller.lineInfo.value.isNotEmpty)
                      controller.lineInfo.value,
                  ].join(" · "),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(
                    () => _OverlayButton(
                      tooltip: controller.showDanmaku.value ? "关闭弹幕" : "开启弹幕",
                      icon: controller.showDanmaku.value
                          ? Remix.message_3_line
                          : Remix.message_3_fill,
                      onPressed: controller.toggleDanmaku,
                    ),
                  ),
                  _OverlayButton(
                    tooltip: "刷新",
                    icon: Remix.refresh_line,
                    onPressed: controller.refreshRoom,
                  ),
                  Obx(
                    () => _OverlayButton(
                      tooltip: controller.muted.value ? "取消静音" : "静音",
                      icon: controller.muted.value
                          ? Remix.volume_mute_line
                          : Remix.volume_up_line,
                      onPressed: controller.toggleMute,
                    ),
                  ),
                  _OverlayButton(
                    tooltip: "移除",
                    icon: Remix.close_line,
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单格的弹幕渲染层。
///
/// 画面按 16:9 `contain` 缩放后不一定铺满格子，这里把弹幕限制在画面实际区域内，
/// 免得弹幕跑到黑边上。行数交给 `AppSettingsController` 按视口高度自适应：
/// 格子矮时行数会被 clamp 变少，太矮时直接隐藏。
class _DanmakuLayer extends StatelessWidget {
  final MultiRoomPlayerController controller;

  const _DanmakuLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth;
        final tileHeight = constraints.maxHeight;
        if (tileWidth <= 0 || tileHeight <= 0) {
          return const SizedBox.shrink();
        }
        // 与 Video 的 BoxFit.contain 保持一致，算出画面实际占据的矩形。
        final videoWidth = tileWidth / tileHeight > 16 / 9
            ? tileHeight * 16 / 9
            : tileWidth;
        final videoHeight = videoWidth * 9 / 16;
        final settings = AppSettingsController.instance;
        final resolvedLineCount = settings.resolveDanmuTargetLineCount(
          viewportHeight: videoHeight,
          area: settings.danmuArea.value,
          fontSize: settings.danmuSize.value,
          lineCount: settings.danmuLineCount.value,
        );
        final hideDanmu = resolvedLineCount <= 0;
        return Center(
          child: SizedBox(
            width: videoWidth,
            height: videoHeight,
            child: IgnorePointer(
              child: DanmakuScreen(
                createdController: controller.initDanmakuController,
                option: DanmakuOption(
                  fontSize: settings.danmuSize.value,
                  fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
                  area: settings.resolveDanmuEffectiveArea(
                    viewportHeight: videoHeight,
                    area: settings.danmuArea.value,
                    fontSize: settings.danmuSize.value,
                    lineCount: settings.danmuLineCount.value,
                  ),
                  lineHeight: settings.resolveDanmuLineHeight(
                    viewportHeight: videoHeight,
                    area: settings.danmuArea.value,
                    fontSize: settings.danmuSize.value,
                    lineCount: settings.danmuLineCount.value,
                  ),
                  duration: settings.danmuSpeed.value.toInt(),
                  opacity: settings.danmuOpacity.value,
                  fontWeight: settings.danmuFontWeight.value,
                  hideTop: hideDanmu,
                  hideBottom: hideDanmu,
                  hideScroll: hideDanmu,
                  hideSpecial: hideDanmu,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _OverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withAlpha(150),
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _CenterText extends StatelessWidget {
  final String text;

  const _CenterText(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: AppStyle.edgeInsetsA8,
        color: Colors.black.withAlpha(150),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
