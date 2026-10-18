import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_focus_policy.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/tv_room_picker.dart';

class MultiRoomPage extends StatefulWidget {
  const MultiRoomPage({super.key});

  static bool _isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.backspace ||
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.browserBack;

  @override
  State<MultiRoomPage> createState() => _MultiRoomPageState();
}

class _MultiRoomPageState extends State<MultiRoomPage> {
  final _addFocusNode = AppFocusNode();
  final _pauseFocusNode = AppFocusNode();
  final _audioFocusNode = AppFocusNode();
  final _refreshFocusNode = AppFocusNode();
  final _settingsFocusNode = AppFocusNode();
  final _backFocusNode = AppFocusNode();
  MultiRoomController get controller => Get.find<MultiRoomController>();

  @override
  void dispose() {
    _addFocusNode.dispose();
    _pauseFocusNode.dispose();
    _audioFocusNode.dispose();
    _refreshFocusNode.dispose();
    _settingsFocusNode.dispose();
    _backFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopScope(
        canPop: controller.allowRoutePop.value,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(controller.handleBack());
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent ||
                !MultiRoomPage._isBackKey(event.logicalKey)) {
              return KeyEventResult.ignored;
            }
            unawaited(controller.handleBack());
            return KeyEventResult.handled;
          },
          child: AppScaffold(
            child: Column(
              children: [
                AppStyle.vGap24,
                _buildToolbar(context),
                AppStyle.vGap16,
                Expanded(
                  child: Obx(() {
                    if (controller.rooms.isEmpty) {
                      return const Center(child: Text('没有正在播放的直播间'));
                    }
                    final expandedKey = controller.expandedRoomKey.value;
                    if (expandedKey != null) {
                      final item = controller.rooms.firstWhereOrNull(
                        (room) => room.key == expandedKey,
                      );
                      if (item != null) {
                        return Padding(
                          padding: EdgeInsets.all(16.w),
                          child: _MultiRoomTile(
                            key: ValueKey(item.key),
                            item: item,
                            index: controller.rooms.indexOf(item),
                            controller: controller,
                          ),
                        );
                      }
                    }
                    final layout =
                        AppSettingsController.instance.multiRoomLayout.value;
                    if (layout == 'mainSub' && controller.rooms.length > 1) {
                      return _buildMainSubLayout();
                    }
                    return _buildGridLayout();
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Row(
      children: [
        AppStyle.hGap32,
        Obx(
          () => Text(
            '多屏同播（${controller.rooms.length}/${controller.roomLimit}）',
            style: AppStyle.titleStyleWhite.copyWith(
              fontSize: 34.w,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Spacer(),
        HighlightButton(
          focusNode: _addFocusNode,
          iconData: Icons.add,
          text: '添加房间',
          onTap: _addRooms,
        ),
        AppStyle.hGap16,
        Obx(
          () => HighlightButton(
            focusNode: _pauseFocusNode,
            iconData: controller.areAllPaused ? Icons.play_arrow : Icons.pause,
            text: controller.areAllPaused ? '全部继续' : '全部暂停',
            onTap: controller.toggleAllPause,
          ),
        ),
        AppStyle.hGap16,
        Obx(
          () => HighlightButton(
            focusNode: _audioFocusNode,
            iconData:
                controller.allMuted.value ? Icons.volume_off : Icons.volume_up,
            text: controller.allMuted.value ? '全部取消静音' : '全部静音',
            onTap: controller.toggleAllAudio,
          ),
        ),
        AppStyle.hGap16,
        HighlightButton(
          focusNode: _refreshFocusNode,
          iconData: Icons.refresh,
          text: '串行刷新',
          onTap: controller.refreshAll,
        ),
        AppStyle.hGap16,
        HighlightButton(
          focusNode: _settingsFocusNode,
          iconData: Icons.tune,
          text: '多屏设置',
          onTap: () => Get.dialog<void>(_MultiRoomSettingsDialog(controller)),
        ),
        AppStyle.hGap16,
        HighlightButton(
          focusNode: _backFocusNode,
          iconData: Icons.close,
          text: '返回',
          onTap: controller.handleBack,
        ),
        AppStyle.hGap32,
      ],
    );
  }

  Widget _buildGridLayout() {
    return Obx(() {
      final count = controller.rooms.length;
      final columns = count <= 1 ? 1 : 2;
      final gap = AppSettingsController.instance.effectiveMultiRoomGap.w;
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(gap, 0, gap, gap),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 16 / 9,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        itemCount: count,
        itemBuilder: (context, index) => _MultiRoomTile(
          key: ValueKey(controller.rooms[index].key),
          item: controller.rooms[index],
          index: index,
          controller: controller,
        ),
      );
    });
  }

  Widget _buildMainSubLayout() {
    return Obx(() {
      final main = controller.rooms.firstWhereOrNull(
            (room) => room.key == controller.mainRoomKey.value,
          ) ??
          controller.rooms.first;
      final secondary =
          controller.rooms.where((room) => room.key != main.key).toList();
      return Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _MultiRoomTile(
                key: ValueKey(main.key),
                item: main,
                index: controller.rooms.indexOf(main),
                controller: controller,
                isMainSubPrimary: true,
              ),
            ),
            AppStyle.hGap16,
            Expanded(
              child: ListView.separated(
                itemCount: secondary.length,
                separatorBuilder: (_, __) => AppStyle.vGap16,
                itemBuilder: (context, index) => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _MultiRoomTile(
                    key: ValueKey(secondary[index].key),
                    item: secondary[index],
                    index: controller.rooms.indexOf(secondary[index]),
                    controller: controller,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _addRooms() async {
    final current = controller.rooms.toList(growable: false);
    final selected = await showTvRoomPicker(
      maxRooms: controller.roomLimit,
      selectedRooms: current,
      existingRooms: current,
    );
    if (selected != null) controller.addRooms(selected);
  }
}

class _MultiRoomTile extends StatefulWidget {
  const _MultiRoomTile({
    super.key,
    required this.item,
    required this.index,
    required this.controller,
    this.isMainSubPrimary = false,
  });

  final MultiRoomItem item;
  final int index;
  final MultiRoomController controller;
  final bool isMainSubPrimary;

  @override
  State<_MultiRoomTile> createState() => _MultiRoomTileState();
}

class _MultiRoomTileState extends State<_MultiRoomTile> {
  late final MultiRoomPlayerController _player =
      widget.controller.playerFor(widget.item);
  late final FocusNode _focusNode = widget.controller.focusNodeFor(widget.item);
  late final Widget _danmakuView = DanmakuScreen(
    key: GlobalKey(),
    createdController: _player.initDanmakuController,
    option: DanmakuOption(
      fontSize: AppSettingsController.instance.danmuSize.value.w,
      fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      area: AppSettingsController.instance.danmuArea.value,
      lineHeight: 1.25,
      emojiScale: 1.4,
      duration: AppSettingsController.instance.danmuSpeed.value.toInt(),
      opacity: AppSettingsController.instance.danmuOpacity.value,
    ),
  );
  bool _focused = false;
  bool _controlsOpen = false;
  final _pauseFocusNode = FocusNode();

  @override
  void dispose() {
    _pauseFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (focused) {
        setState(() {
          _focused = focused;
          if (!focused) _controlsOpen = false;
        });
        if (focused) widget.controller.focusedRoomKey.value = widget.item.key;
      },
      onKeyEvent: (_, event) => _onKeyEvent(event),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: AppStyle.radius16,
          border: Border.all(
            color: _focused ? Colors.lightBlueAccent : Colors.white24,
            width: _focused ? 4.w : 1.w,
          ),
          boxShadow: _focused
              ? const [BoxShadow(color: Colors.black54, blurRadius: 18)]
              : const [],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Obx(() {
              _player.renderRevision.value;
              final videoController = _player.videoController;
              if (videoController == null || _player.isReleasedForMemory) {
                return Center(
                  child: Text(
                    _player.isReleasedForMemory ? '资源已释放' : '等待播放器',
                    style: TextStyle(color: Colors.white70, fontSize: 24.w),
                  ),
                );
              }
              return Video(
                key: ValueKey(
                    '${widget.item.key}-${_player.renderRevision.value}'),
                controller: videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              );
            }),
            Positioned.fill(
              child: Obx(() {
                if (_player.loading.value) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 3));
                }
                if (_player.errorText.value.isNotEmpty) {
                  final isOffline =
                      _player.liveState.value == LiveStatusState.offline;
                  return _CenterText(
                    _player.errorText.value,
                    action: _player.isReleasedForMemory
                        ? '按确定手动恢复'
                        : isOffline
                            ? null
                            : '按确定重试',
                  );
                }
                if (_player.liveState.value == LiveStatusState.offline) {
                  return const _CenterText('未开播');
                }
                return const SizedBox.shrink();
              }),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
                color: Colors.black.withAlpha(170),
                child: Row(
                  children: [
                    Container(
                      width: 34.w,
                      height: 34.w,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 20.w,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Obx(
                        () => Text(
                          '${widget.item.site.name} · ${_player.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 24.w),
                        ),
                      ),
                    ),
                    Obx(
                      () =>
                          widget.controller.mainRoomKey.value == widget.item.key
                              ? Padding(
                                  padding: EdgeInsets.only(left: 12.w),
                                  child: Text(
                                    '主画面',
                                    style: TextStyle(
                                      color: Colors.lightBlueAccent,
                                      fontSize: 18.w,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12.w,
              right: 12.w,
              bottom: 8.w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Obx(
                    () => Offstage(
                      offstage: !_player.showDanmakuState.value,
                      child: SizedBox(height: 180.w, child: _danmakuView),
                    ),
                  ),
                  if (_controlsOpen && _focused)
                    Obx(() => _buildControls(context)),
                  if (!_controlsOpen && _focused)
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.w),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: AppStyle.radius8,
                      ),
                      child: Text(
                        'OK 控制  ·  Menu 设置  ·  ${widget.index + 1}号房间',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 17.w),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 12.w,
              top: 58.w,
              child: Obx(
                () => Text(
                  [
                    if (_player.qualityDisplayInfo.isNotEmpty)
                      _player.qualityDisplayInfo,
                    if (_player.lineInfo.value.isNotEmpty)
                      _player.lineInfo.value,
                    _player.userPaused.value ? '已暂停' : '播放中',
                    _player.muted.value ? '静音' : '有声',
                  ].join(' · '),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 17.w,
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isDirectionKey = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (isDirectionKey &&
        !_controlsOpen &&
        AppSettingsController.instance.multiRoomLayout.value == 'grid' &&
        !widget.controller.isExpanded) {
      final targetIndex = MultiRoomFocusPolicy.nextGridIndex(
        currentIndex: widget.index,
        roomCount: widget.controller.rooms.length,
        columnCount: widget.controller.rooms.length <= 1 ? 1 : 2,
        key: event.logicalKey,
      );
      if (targetIndex != null) {
        widget.controller
            .focusNodeFor(widget.controller.rooms[targetIndex])
            .requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_player.isReleasedForMemory) {
        unawaited(widget.controller.recoverReleasedRoom(widget.item));
      } else if (_player.errorText.value.isNotEmpty &&
          _player.liveState.value != LiveStatusState.offline) {
        unawaited(widget.controller.refreshRoom(widget.item));
      } else {
        setState(() => _controlsOpen = !_controlsOpen);
        if (_controlsOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _controlsOpen) _pauseFocusNode.requestFocus();
          });
        }
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
        event.logicalKey == LogicalKeyboardKey.keyM) {
      unawaited(Get.dialog<void>(_MultiRoomSettingsDialog(widget.controller)));
      return KeyEventResult.handled;
    }
    if (MultiRoomPage._isBackKey(event.logicalKey)) {
      if (_controlsOpen) {
        setState(() => _controlsOpen = false);
        _focusNode.requestFocus();
      } else {
        unawaited(widget.controller.handleBack());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildControls(BuildContext context) {
    final buttonSize = 38.w;
    Widget button({
      required String label,
      required IconData icon,
      required Future<void> Function() onPressed,
      bool autofocus = false,
    }) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event.logicalKey != LogicalKeyboardKey.select &&
              event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.numpadEnter) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) unawaited(onPressed());
          return KeyEventResult.handled;
        },
        child: IconButton(
          tooltip: label,
          focusNode: autofocus ? _pauseFocusNode : null,
          iconSize: buttonSize,
          color: Colors.white,
          onPressed: () => unawaited(onPressed()),
          icon: Icon(icon),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.w),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(220),
        borderRadius: AppStyle.radius12,
        border: Border.all(color: Colors.white30),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2.w,
        children: [
          button(
            label: _player.userPaused.value ? '继续' : '暂停',
            icon: _player.userPaused.value ? Icons.play_arrow : Icons.pause,
            onPressed: _player.togglePause,
            autofocus: true,
          ),
          button(
              label: '音量减',
              icon: Icons.volume_down,
              onPressed: () =>
                  widget.controller.changeRoomVolume(widget.item, -8)),
          button(
              label: '音量加',
              icon: Icons.volume_up,
              onPressed: () =>
                  widget.controller.changeRoomVolume(widget.item, 8)),
          button(
            label: _player.muted.value ? '取消静音' : '静音',
            icon: _player.muted.value ? Icons.volume_off : Icons.volume_mute,
            onPressed: () => widget.controller.toggleAudio(widget.item),
          ),
          PopupMenuButton<int>(
            tooltip: '清晰度',
            icon: const Icon(Icons.high_quality, color: Colors.white),
            onSelected: (index) => unawaited(
                widget.controller.selectRoomQuality(widget.item, index)),
            itemBuilder: (_) => [
              for (var index = 0; index < _player.qualities.length; index++)
                PopupMenuItem(
                  value: index,
                  child: Text(_player.qualities[index].quality),
                ),
            ],
          ),
          PopupMenuButton<int>(
            tooltip: '线路',
            icon: const Icon(Icons.alt_route, color: Colors.white),
            onSelected: (index) =>
                unawaited(widget.controller.selectRoomLine(widget.item, index)),
            itemBuilder: (_) => [
              for (var index = 0; index < _player.lineCount; index++)
                PopupMenuItem(value: index, child: Text('线路 ${index + 1}')),
            ],
          ),
          button(
              label: '刷新',
              icon: Icons.refresh,
              onPressed: () => widget.controller.refreshRoom(widget.item)),
          button(
              label: '设为主画面',
              icon: Icons.star_outline,
              onPressed: () async =>
                  widget.controller.setMainRoom(widget.item)),
          button(
            label: widget.controller.isExpanded ? '还原布局' : '放大',
            icon: widget.controller.isExpanded
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
            onPressed: () => widget.controller.toggleExpanded(widget.item),
          ),
          button(
              label: '转为单路播放',
              icon: Icons.open_in_full,
              onPressed: _openAsSingleRoom),
          button(
              label: '移除',
              icon: Icons.close,
              onPressed: () => widget.controller.removeRoom(widget.item)),
        ],
      ),
    );
  }

  Future<void> _openAsSingleRoom() async {
    await widget.controller.closePlaybackSession();
    await AppNavigator.toLiveRoomDetail(
      site: widget.item.site,
      roomId: widget.item.roomId,
      douyinSecUserId: widget.item.douyinSecUserId,
      xiaohongshuHostId: widget.item.xiaohongshuHostId,
      replaceCurrentRoute: true,
    );
  }
}

class _CenterText extends StatelessWidget {
  const _CenterText(this.text, {this.action});

  final String text;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(180),
          borderRadius: AppStyle.radius12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 23.w),
            ),
            if (action != null) ...[
              SizedBox(height: 8.w),
              Text(action!,
                  style: TextStyle(color: Colors.white60, fontSize: 16.w)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MultiRoomSettingsDialog extends StatelessWidget {
  const _MultiRoomSettingsDialog(this.controller);

  final MultiRoomController controller;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Dialog(
      child: SizedBox(
        width: 620,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('多屏设置', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              if (Platform.isAndroid)
                Obx(
                  () => DropdownButtonFormField<int>(
                    initialValue: settings.multiRoomMaxRooms.value,
                    decoration: const InputDecoration(labelText: '最大同时播放路数'),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('2 路（默认）')),
                      DropdownMenuItem(value: 4, child: Text('4 路')),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.setMultiRoomMaxRooms(value);
                    },
                  ),
                ),
              Obx(
                () => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'grid', label: Text('网格布局')),
                    ButtonSegment(value: 'mainSub', label: Text('主画面 + 副画面')),
                  ],
                  selected: {settings.multiRoomLayout.value},
                  onSelectionChanged: (selection) {
                    settings.setMultiRoomLayout(selection.first);
                  },
                ),
              ),
              Obx(
                () => SwitchListTile(
                  value: settings.multiRoomMixAudio.value,
                  title: const Text('允许多路混音'),
                  onChanged: controller.setMixAudio,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  autofocus: true,
                  onPressed: Get.back<void>,
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
