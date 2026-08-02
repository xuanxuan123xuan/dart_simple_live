import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/chat_message_item.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';

class MultiRoomPage extends GetView<MultiRoomController> {
  const MultiRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: controller.toggleOverlay,
        child: Stack(
          children: [
            // 画面网格
            LayoutBuilder(
              builder: (context, constraints) => Obx(
                () {
                  final rooms = controller.rooms.toList();
                  if (rooms.isEmpty) {
                    return const _CenterText("没有可播放的直播间");
                  }
                  final gap = AppSettingsController
                      .instance.effectiveMultiRoomGap
                      .toDouble();
                  final mainSubLayoutActive = controller.isMainSubLayoutActive;
                  final chatPanelRatio = controller.chatPanelRatio.value;
                  // 双击聚焦模式：只显示单个直播间全屏。
                  final focusKey = controller.focusedRoomKey.value;
                  if (focusKey != null) {
                    final idx = rooms.indexWhere((r) => r.key == focusKey);
                    if (idx >= 0) {
                      return Padding(
                        padding: EdgeInsets.all(gap),
                        child: _tileAt(idx, rooms),
                      );
                    }
                  }
                  final showChat = AppSettingsController
                          .instance.multiRoomShowChatPanel.value &&
                      (rooms.length == 2 || rooms.length == 3);
                  if (showChat) {
                    return _buildChatPanelLayout(
                      rooms,
                      constraints,
                      gap,
                      mainSubLayoutActive: mainSubLayoutActive,
                      chatPanelRatio: chatPanelRatio,
                    );
                  }
                  if (mainSubLayoutActive) {
                    return _buildMainSubRoomLayout(rooms, gap);
                  }
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
            // 顶部覆盖层：点击画面切换显隐，8 秒自动隐藏，尺寸与播放器全屏控件一致
            Obx(
              () => AnimatedPositioned(
                left: 0,
                right: 0,
                top: controller.showOverlay.value
                    ? 0
                    : -(56 + MediaQuery.of(context).viewPadding.top),
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // 拦截点击，避免冒泡到外层 GestureDetector 触发 toggleOverlay
                  // （那会导致页面 rebuild，弹窗刚打开就被 pop）。
                  onTap: () {},
                  child: Container(
                    height: 56 + MediaQuery.of(context).viewPadding.top,
                    padding: EdgeInsets.only(
                      left: 32,
                      right: 32,
                      top: MediaQuery.of(context).viewPadding.top,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: "返回",
                          onPressed: () {
                            if (controller.focusedRoomKey.value != null) {
                              controller.exitFocus();
                            } else {
                              Get.back();
                            }
                          },
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Obx(
                            () => Text(
                              controller.focusedRoomKey.value != null
                                  ? "聚焦中"
                                  : "多开同屏（${controller.rooms.length}）",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 18),
                            ),
                          ),
                        ),
                        if (controller.adaptiveQualityStatus.value.isNotEmpty ||
                            controller.totalBandwidthMbps.value != null)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              [
                                if (controller
                                    .adaptiveQualityStatus.value.isNotEmpty)
                                  controller.adaptiveQualityStatus.value,
                                if (controller.totalBandwidthMbps.value != null)
                                  "${controller.totalBandwidthMbps.value!.toStringAsFixed(1)} Mbps",
                              ].join(" · "),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        if (controller.focusedRoomKey.value != null)
                          IconButton(
                            tooltip: "转到单直播间",
                            onPressed: controller.openingSingleRoom.value
                                ? null
                                : controller.openFocusedRoomAsSingle,
                            icon: const Icon(Icons.open_in_new,
                                color: Colors.white),
                          ),
                        IconButton(
                          tooltip: "加入直播间",
                          onPressed: controller.canAddRoom
                              ? () => _showAddRoomSheet(context)
                              : null,
                          icon: Icon(
                            Remix.play_list_add_line,
                            color: controller.canAddRoom
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                        if (controller.canToggleMainSubLayout)
                          IconButton(
                            tooltip: controller.mainSubLayout.value
                                ? "切换为均分布局"
                                : "切换为 1+${controller.rooms.length - 1} 主次布局",
                            onPressed: controller.toggleMainSubLayout,
                            icon: Icon(
                              controller.mainSubLayout.value
                                  ? Icons.view_column_outlined
                                  : Icons.grid_view_outlined,
                              color: controller.mainSubLayout.value
                                  ? Colors.amber
                                  : Colors.white,
                            ),
                          ),
                        IconButton(
                          tooltip: controller.allPaused.value ? "全部继续" : "全部暂停",
                          onPressed: controller.toggleAllPaused,
                          icon: Icon(
                            controller.allPaused.value
                                ? Icons.play_arrow
                                : Icons.pause,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: "全部静音",
                          onPressed: controller.muteAll,
                          icon: const Icon(Remix.volume_mute_line,
                              color: Colors.white),
                        ),
                        IconButton(
                          tooltip: controller.isRefreshingAll.value
                              ? "正在刷新 ${controller.refreshProgress.value}"
                              : "全部刷新",
                          onPressed: controller.isRefreshingAll.value
                              ? null
                              : controller.refreshAllRooms,
                          icon: controller.isRefreshingAll.value
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Remix.refresh_line,
                                  color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSubRoomLayout(
    List<MultiRoomItem> rooms,
    double gap,
  ) {
    return Padding(
      padding: EdgeInsets.all(gap),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _tileAt(0, rooms, loadDanmaku: true),
          ),
          SizedBox(width: gap),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                for (var i = 1; i < rooms.length; i += 1) ...[
                  if (i > 1) SizedBox(height: gap),
                  Expanded(
                    child: _tileAt(i, rooms, loadDanmaku: false),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileAt(int index, List<MultiRoomItem> rooms,
      {bool loadDanmaku = true}) {
    // 最后一行可能不满，空位留空白占位以保持每格等宽。
    if (index >= rooms.length) {
      return const SizedBox.shrink();
    }
    final room = rooms[index];
    final tile = _MultiRoomTile(
      item: room,
      controller: controller.playerFor(room),
      onRemove: () => controller.removeRoom(room),
      onSetMain: () => controller.setMainRoom(room.key),
      onTogglePaused: () => controller.toggleRoomPaused(room),
      onToggleAudio: () => controller.toggleRoomAudio(room),
      refreshDisabled: controller.isRefreshingAll.value,
      isMain: index == 0 && controller.isMainSubLayoutActive,
      loadDanmaku: loadDanmaku,
    );
    return GestureDetector(
      // 双击聚焦单格，再双击或点返回退出。
      onDoubleTap: () => controller.focusRoom(room.key),
      child: AnimatedSwitcher(
        key: ValueKey(room.key),
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) {
            controller.swapRooms(details.data, index);
          },
          builder: (ctx, candidates, rejected) {
            return Opacity(
              opacity: candidates.isNotEmpty ? 0.8 : 1,
              child: LongPressDraggable<int>(
                data: index,
                delay: const Duration(milliseconds: 300),
                feedback: Opacity(
                  opacity: 0.85,
                  child: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: MediaQuery.of(ctx).size.width * 0.4,
                      child: _MultiRoomTile(
                        item: room,
                        controller: controller.playerFor(room),
                        onRemove: () => {},
                        isMain: index == 0 && controller.isMainSubLayoutActive,
                        loadDanmaku: loadDanmaku,
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.4,
                  child: tile,
                ),
                child: tile,
              ),
            );
          },
        ),
      ),
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
      final videoWidth =
          cellWidth / cellHeight > 16 / 9 ? cellHeight * 16 / 9 : cellWidth;
      final videoHeight = videoWidth * 9 / 16;
      final area = videoWidth * videoHeight;
      if (area > bestArea) {
        bestArea = area;
        bestColumns = columns;
      }
    }
    return bestColumns;
  }

  Widget _buildChatPanelLayout(
    List<MultiRoomItem> rooms,
    BoxConstraints constraints,
    double gap, {
    required bool mainSubLayoutActive,
    required double chatPanelRatio,
  }) {
    final chatRoomIndex =
        controller.chatTargetIndex.value.clamp(0, rooms.length - 1);
    final chatController = controller.playerFor(rooms[chatRoomIndex]);

    if (rooms.length == 2) {
      return Padding(
        padding: EdgeInsets.all(gap),
        child: LayoutBuilder(
          builder: (ctx, innerConstraints) {
            final chatWidth =
                _chatPanelWidth(innerConstraints.maxWidth, gap, chatPanelRatio);
            final dragHandle =
                _buildChatResizeHandle(innerConstraints.maxWidth, gap);
            // 主次布局：左主格 + 右（上次直播间小 + 下聊天区大）。
            if (mainSubLayoutActive) {
              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _tileAt(0, rooms, loadDanmaku: true),
                  ),
                  SizedBox(width: gap),
                  dragHandle,
                  SizedBox(width: gap),
                  SizedBox(
                    width: chatWidth,
                    child: Column(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _tileAt(1, rooms, loadDanmaku: false),
                        ),
                        SizedBox(height: gap),
                        Expanded(
                          flex: 3,
                          child: _ChatPanel(
                            rooms: rooms,
                            chatController: chatController,
                            chatRoomIndex: chatRoomIndex,
                            onSelect: (i) =>
                                controller.chatTargetIndex.value = i,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _tileAt(0, rooms)),
                      SizedBox(height: gap),
                      Expanded(child: _tileAt(1, rooms)),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                dragHandle,
                SizedBox(width: gap),
                SizedBox(
                  width: chatWidth,
                  child: _ChatPanel(
                    rooms: rooms,
                    chatController: chatController,
                    chatRoomIndex: chatRoomIndex,
                    onSelect: (i) => controller.chatTargetIndex.value = i,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.all(gap),
      child: LayoutBuilder(
        builder: (ctx, innerConstraints) {
          final chatColumnWidth =
              _chatPanelWidth(innerConstraints.maxWidth, gap, chatPanelRatio);
          final dragHandle =
              _buildChatResizeHandle(innerConstraints.maxWidth, gap);
          return Row(
            children: [
              Expanded(
                child: mainSubLayoutActive
                    ? _tileAt(0, rooms, loadDanmaku: true)
                    : Column(
                        children: [
                          Expanded(child: _tileAt(0, rooms)),
                          SizedBox(height: gap),
                          Expanded(child: _tileAt(2, rooms)),
                        ],
                      ),
              ),
              SizedBox(width: gap),
              dragHandle,
              SizedBox(width: gap),
              SizedBox(
                width: chatColumnWidth,
                child: Column(
                  children: [
                    Expanded(
                      flex: mainSubLayoutActive ? 2 : 1,
                      child: mainSubLayoutActive
                          ? Row(
                              children: [
                                Expanded(
                                  child: _tileAt(
                                    1,
                                    rooms,
                                    loadDanmaku: false,
                                  ),
                                ),
                                SizedBox(width: gap),
                                Expanded(
                                  child: _tileAt(
                                    2,
                                    rooms,
                                    loadDanmaku: false,
                                  ),
                                ),
                              ],
                            )
                          : _tileAt(1, rooms),
                    ),
                    SizedBox(height: gap),
                    Expanded(
                      flex: mainSubLayoutActive ? 3 : 1,
                      child: _ChatPanel(
                        rooms: rooms,
                        chatController: chatController,
                        chatRoomIndex: chatRoomIndex,
                        onSelect: (i) => controller.chatTargetIndex.value = i,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const double _chatResizeHandleWidth = 24;

  double _chatPanelWidth(
    double availableWidth,
    double gap,
    double chatPanelRatio,
  ) {
    final contentWidth = availableWidth - _chatResizeHandleWidth - gap * 2;
    final resizableWidth = contentWidth > 0 ? contentWidth : 0.0;
    return (resizableWidth * chatPanelRatio).clamp(
      resizableWidth * 0.2,
      resizableWidth * 0.6,
    );
  }

  Widget _buildChatResizeHandle(double availableWidth, double gap) {
    final contentWidth = availableWidth - _chatResizeHandleWidth - gap * 2;
    final resizableWidth = contentWidth > 0 ? contentWidth : 1.0;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          // 聊天区位于手柄右侧：手柄右移时宽度应减小。
          controller.changeChatPanelRatio(
            controller.chatPanelRatio.value - details.delta.dx / resizableWidth,
          );
        },
        child: Container(
          width: _chatResizeHandleWidth,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 3,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white38,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddRoomSheet(BuildContext context) {
    final tabIndex = 0.obs;
    final alreadyInRoom = <String>{for (final r in controller.rooms) r.key};

    // 延后到当前指针事件结束后再打开，避免打开按钮的
    // 残留手势命中新弹层，同时保留点击遮罩和下滑关闭。
    _showStableBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: AppStyle.bottomSheetPadding(),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.only(left: 12),
                title: const Text("加入直播间"),
                trailing: IconButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Remix.close_line),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Obx(() => Row(
                            children: [
                              _TabChip("关注(直播中)", tabIndex.value == 0,
                                  () => tabIndex.value = 0),
                              const SizedBox(width: 8),
                              _TabChip("历史", tabIndex.value == 1,
                                  () => tabIndex.value = 1),
                            ],
                          )),
                    ),
                    Expanded(
                      child: Obx(() {
                        if (tabIndex.value == 1) {
                          return _buildHistoryTab(alreadyInRoom);
                        }
                        return _buildFollowTab(alreadyInRoom);
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFollowTab(Set<String> alreadyInRoom) {
    final liveList = FollowService.instance.liveList;
    if (liveList.isEmpty) {
      return const Center(
          child: Text("没有直播中的关注", style: TextStyle(color: Colors.white70)));
    }
    return ListView.builder(
      itemCount: liveList.length,
      itemBuilder: (_, i) {
        final item = liveList[i];
        final added =
            alreadyInRoom.contains(MultiRoomItem.fromFollow(item).key);
        return FollowUserItem(
          item: item,
          playing: added,
          onTap: () {
            if (!added) {
              Get.back();
              controller.addRoomFromFollow(item);
            }
          },
        );
      },
    );
  }

  Widget _buildHistoryTab(Set<String> alreadyInRoom) {
    final histories = DBService.instance.getHistores();
    if (histories.isEmpty) {
      return const Center(
          child: Text("没有历史记录", style: TextStyle(color: Colors.white70)));
    }
    return ListView.builder(
      itemCount: histories.length,
      itemBuilder: (_, i) {
        final item = histories[i];
        final site = Sites.allSites[item.siteId];
        final added = alreadyInRoom.contains("${item.siteId}_${item.roomId}");
        return ListTile(
          leading: site != null
              ? Image.asset(site.logo, width: 32, height: 32)
              : const Icon(Icons.live_tv, color: Colors.white54),
          title: Text(item.userName,
              style: TextStyle(color: added ? Colors.white38 : Colors.white)),
          subtitle: Text(site?.name ?? item.siteId,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          enabled: !added,
          onTap: () {
            if (!added) {
              Get.back();
              controller.addRoomFromHistory(item);
            }
          },
        );
      },
    );
  }
}

class _ChatPanel extends StatefulWidget {
  final List<MultiRoomItem> rooms;
  final MultiRoomPlayerController chatController;
  final int chatRoomIndex;
  final void Function(int) onSelect;

  const _ChatPanel({
    required this.rooms,
    required this.chatController,
    required this.chatRoomIndex,
    required this.onSelect,
  });

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.rooms;
    final chatController = widget.chatController;
    final chatRoomIndex = widget.chatRoomIndex;
    final onSelect = widget.onSelect;
    return ClipRRect(
      borderRadius: AppStyle.radius8,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(120),
          borderRadius: AppStyle.radius8,
        ),
        child: Column(
          children: [
            // 顶部直播间选择按钮行
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: List.generate(rooms.length, (i) {
                  final room = rooms[i];
                  final selected = i == chatRoomIndex;
                  return GestureDetector(
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected ? Colors.white30 : Colors.transparent,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            room.site.logo,
                            width: 20,
                            height: 20,
                            opacity: selected
                                ? const AlwaysStoppedAnimation(1)
                                : const AlwaysStoppedAnimation(0.5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            room.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white54,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            // 竖向弹幕列表
            Expanded(
              child: Obx(() {
                final msgs = chatController.chatMessages;
                if (msgs.isEmpty) {
                  return const Center(
                    child: Text("暂无弹幕",
                        style: TextStyle(color: Colors.white24, fontSize: 12)),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg = msgs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: ChatMessageItem(message: msg),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.white10,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 14,
            )),
      ),
    );
  }
}

class _MultiRoomTile extends StatefulWidget {
  final MultiRoomItem item;
  final MultiRoomPlayerController controller;
  final VoidCallback onRemove;
  final VoidCallback? onSetMain;
  final VoidCallback? onTogglePaused;
  final VoidCallback? onToggleAudio;
  final bool isMain;
  final bool refreshDisabled;

  /// 是否渲染画面弹幕层（1+3 主次布局的小格传 false）。
  final bool loadDanmaku;

  const _MultiRoomTile({
    required this.item,
    required this.controller,
    required this.onRemove,
    this.onSetMain,
    this.onTogglePaused,
    this.onToggleAudio,
    this.isMain = false,
    this.refreshDisabled = false,
    this.loadDanmaku = true,
  });

  @override
  State<_MultiRoomTile> createState() => _MultiRoomTileState();
}

class _MultiRoomTileState extends State<_MultiRoomTile> {
  bool _showVolumeSlider = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final controller = widget.controller;
    final onRemove = widget.onRemove;
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
            if (widget.loadDanmaku)
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
              left: 6,
              top: 6,
              // 状态徽标：断流重试 / 弹幕重连
              child: Obx(() {
                final status = controller.streamStatus.value;
                if (status.isEmpty) {
                  return const SizedBox.shrink();
                }
                final isStream = status.contains("重试中");
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isStream
                        ? Colors.red.withAlpha(200)
                        : Colors.amber.withAlpha(200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                );
              }),
            ),
            if (widget.onSetMain != null)
              Positioned(
                right: 4,
                top: 4,
                child: _OverlayButton(
                  tooltip: widget.isMain ? "当前主画面" : "设为主画面",
                  icon:
                      widget.isMain ? Icons.push_pin : Icons.push_pin_outlined,
                  onPressed: widget.isMain ? null : widget.onSetMain!,
                  color: widget.isMain ? Colors.amber : Colors.white,
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Obx(
                () => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${item.site.name} · ${item.userName}",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    if (controller.qualityInfo.value.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _InfoChip(
                        text: controller.qualityInfo.value,
                        onTap: () => _showTileQualitySheet(context, controller),
                      ),
                    ],
                    if (controller.lineInfo.value.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _InfoChip(
                        text: controller.lineInfo.value,
                        onTap: () => _showTileLineSheet(context, controller),
                      ),
                    ],
                  ],
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
                    tooltip: controller.paused.value ? "继续播放" : "暂停播放",
                    icon: controller.paused.value
                        ? Icons.play_arrow
                        : Icons.pause,
                    onPressed: widget.onTogglePaused ?? controller.togglePaused,
                  ),
                  _OverlayButton(
                    tooltip: "刷新",
                    icon: Remix.refresh_line,
                    onPressed:
                        widget.refreshDisabled ? null : controller.refreshRoom,
                  ),
                  Obx(
                    () => _OverlayButton(
                      tooltip: controller.muted.value ? "取消静音" : "调节音量",
                      icon: controller.muted.value
                          ? Remix.volume_mute_line
                          : Remix.volume_up_line,
                      onPressed: () {
                        if (controller.muted.value) {
                          (widget.onToggleAudio ?? controller.toggleMute)
                              .call();
                        } else {
                          setState(
                              () => _showVolumeSlider = !_showVolumeSlider);
                        }
                      },
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
            // 音量滑条
            Positioned(
              right: 4,
              bottom: 48,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _showVolumeSlider ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_showVolumeSlider,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SizedBox(
                      width: 180,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: "静音此直播间",
                            onPressed: () {
                              (widget.onToggleAudio ?? controller.toggleMute)
                                  .call();
                              setState(() => _showVolumeSlider = false);
                            },
                            icon: const Icon(
                              Remix.volume_mute_line,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          Expanded(
                            child: Obx(
                              () => Slider(
                                value: controller.volume.value,
                                min: 0,
                                max: 100,
                                onChanged: controller.setVolume,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
        final videoWidth =
            tileWidth / tileHeight > 16 / 9 ? tileHeight * 16 / 9 : tileWidth;
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

/// 每格底部可点击的信息胶囊（清晰度/线路）。
class _InfoChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _InfoChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(160),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}

void _showTileQualitySheet(
  BuildContext context,
  MultiRoomPlayerController controller,
) {
  final qualities = controller.qualities;
  if (qualities.isEmpty) return;
  _showStableBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text(
              "选择清晰度",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: IconButton(
              tooltip: "关闭",
              onPressed: () => Navigator.of(sheetContext).pop(),
              icon: const Icon(Remix.close_line),
            ),
          ),
          Obx(
            () => ListTile(
              title: const Text("自动"),
              subtitle: const Text("允许多开根据缓冲、内存和设备负载调整"),
              trailing: controller.qualityLocked.value
                  ? null
                  : const Icon(Icons.check, size: 18),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.useAutomaticQuality();
              },
            ),
          ),
          for (var i = 0; i < qualities.length; i++)
            ListTile(
              title: Text(qualities[i].quality),
              trailing: i == controller.qualityIndex
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.changeQuality(i);
              },
            ),
        ],
      ),
    ),
  );
}

void _showTileLineSheet(
  BuildContext context,
  MultiRoomPlayerController controller,
) {
  final urls = controller.playUrls;
  if (urls.isEmpty) return;
  _showStableBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text(
              "选择线路",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: IconButton(
              tooltip: "关闭",
              onPressed: () => Navigator.of(sheetContext).pop(),
              icon: const Icon(Remix.close_line),
            ),
          ),
          for (var i = 0; i < urls.length; i++)
            ListTile(
              title: Text("线路${i + 1}"),
              trailing: i == controller.lineIndex
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.changeLine(i);
              },
            ),
        ],
      ),
    ),
  );
}

bool _stableBottomSheetActive = false;

void _showStableBottomSheet({
  required BuildContext context,
  required WidgetBuilder builder,
  ShapeBorder? shape,
}) {
  if (_stableBottomSheetActive) return;
  _stableBottomSheetActive = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      _stableBottomSheetActive = false;
      return;
    }
    try {
      showModalBottomSheet<void>(
        context: context,
        shape: shape,
        // 延后打开已隔离发起手势，这里可以保留标准关闭交互。
        isDismissible: true,
        enableDrag: true,
        builder: builder,
      ).whenComplete(() => _stableBottomSheetActive = false);
    } catch (_) {
      _stableBottomSheetActive = false;
      rethrow;
    }
  });
  WidgetsBinding.instance.scheduleFrame();
}

class _OverlayButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  const _OverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withAlpha(150),
          foregroundColor: color,
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
