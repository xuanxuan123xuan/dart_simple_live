import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_focus_policy.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_overlay_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/widgets/tv_room_picker.dart';

class MultiRoomPage extends StatefulWidget {
  const MultiRoomPage({super.key});

  static bool _isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.backspace ||
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.browserBack;

  static bool _isActivateKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  @override
  State<MultiRoomPage> createState() => _MultiRoomPageState();
}

class _MultiRoomPageState extends State<MultiRoomPage> {
  final FocusNode _addRoomsFocusNode = FocusNode(debugLabel: 'add rooms');
  final FocusNode _layoutFocusNode = FocusNode(debugLabel: 'room layout');
  final FocusNode _globalMoreFocusNode = FocusNode(debugLabel: 'global more');
  final FocusNode _pauseFocusNode =
      FocusNode(debugLabel: 'selected room pause');
  final FocusNode _soundFocusNode =
      FocusNode(debugLabel: 'selected room sound');
  final FocusNode _danmakuFocusNode =
      FocusNode(debugLabel: 'selected room danmaku');
  final FocusNode _qualityFocusNode =
      FocusNode(debugLabel: 'selected room quality');
  final FocusNode _lineFocusNode = FocusNode(debugLabel: 'selected room line');
  final FocusNode _roomMoreFocusNode =
      FocusNode(debugLabel: 'selected room more');
  final Map<String, GlobalKey<_MultiRoomTileState>> _tileKeys = {};
  late final MultiRoomOverlayController _overlay = MultiRoomOverlayController(
    onBeforeHide: _returnFocusBeforeHide,
  );
  Offset? _lastHoverPosition;
  bool _initialFocusScheduled = false;
  bool _suppressFocusActivity = false;
  int _overlayHoldCount = 0;

  MultiRoomController get controller => Get.find<MultiRoomController>();

  @override
  void dispose() {
    _overlay.dispose();
    _addRoomsFocusNode.dispose();
    _layoutFocusNode.dispose();
    _globalMoreFocusNode.dispose();
    _pauseFocusNode.dispose();
    _soundFocusNode.dispose();
    _danmakuFocusNode.dispose();
    _qualityFocusNode.dispose();
    _lineFocusNode.dispose();
    _roomMoreFocusNode.dispose();
    _tileKeys.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopScope(
        canPop: controller.allowRoutePop.value,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_handleBack());
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (MultiRoomPage._isBackKey(event.logicalKey)) {
              unawaited(_handleBack());
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                event.logicalKey == LogicalKeyboardKey.keyM) {
              _overlay.activity();
              unawaited(_showGlobalMore());
              return KeyEventResult.handled;
            }
            _overlay.activity();
            return KeyEventResult.ignored;
          },
          child: AnimatedBuilder(
            animation: _overlay,
            builder: (context, _) => Obx(_buildPage),
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    final rooms = controller.rooms.toList(growable: false);
    _scheduleInitialFocus(rooms);
    final selectedRoom = _selectedRoom(rooms);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (event) {
          if (_lastHoverPosition != event.position) {
            _lastHoverPosition = event.position;
            _overlay.activity();
          }
        },
        onPointerDown: (event) {
          _lastHoverPosition = event.position;
          _overlay.activity();
        },
        onPointerSignal: (_) => _overlay.activity(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildRoomLayout(rooms, selectedRoom)),
            _buildTopOverlay(rooms.length),
            _buildBottomOverlay(rooms, selectedRoom),
          ],
        ),
      ),
    );
  }

  void _scheduleInitialFocus(List<MultiRoomItem> rooms) {
    if (_initialFocusScheduled || rooms.isEmpty) return;
    _initialFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedRoom = _selectedRoom(rooms);
      if (selectedRoom != null) {
        controller.focusNodeFor(selectedRoom).requestFocus();
      }
    });
  }

  MultiRoomItem? _selectedRoom(List<MultiRoomItem> rooms) {
    if (rooms.isEmpty) return null;
    final focusedKey = controller.focusedRoomKey.value;
    for (final room in rooms) {
      if (room.key == focusedKey) return room;
    }
    final mainKey = controller.mainRoomKey.value;
    for (final room in rooms) {
      if (room.key == mainKey) return room;
    }
    return rooms.first;
  }

  GlobalKey<_MultiRoomTileState> _tileKeyFor(MultiRoomItem item) =>
      _tileKeys.putIfAbsent(
        item.key,
        () => GlobalKey<_MultiRoomTileState>(debugLabel: 'multi-room-tile'),
      );

  Widget _buildRoomLayout(
    List<MultiRoomItem> rooms,
    MultiRoomItem? selectedRoom,
  ) {
    if (rooms.isEmpty) {
      return const Center(
        child: Text(
          '没有正在播放的直播间',
          style: TextStyle(color: Colors.white70, fontSize: 24),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedKey = controller.expandedRoomKey.value;
        if (expandedKey != null) {
          final expanded =
              rooms.firstWhereOrNull((room) => room.key == expandedKey);
          if (expanded != null) {
            return _roomTile(expanded, rooms, selectedRoom);
          }
        }

        final layout = AppSettingsController.instance.multiRoomLayout.value;
        if (rooms.length == 2) {
          return _buildTwoRoomLayout(
            rooms,
            selectedRoom,
            constraints.biggest,
            mainSub: layout == 'mainSub',
          );
        }
        if (layout == 'mainSub' && rooms.length > 1) {
          return _buildMainSubLayout(rooms, selectedRoom, constraints.biggest);
        }
        return _buildGridLayout(rooms, selectedRoom, constraints.biggest);
      },
    );
  }

  Widget _roomTile(
    MultiRoomItem item,
    List<MultiRoomItem> rooms,
    MultiRoomItem? selectedRoom,
  ) {
    return _MultiRoomTile(
      key: _tileKeyFor(item),
      item: item,
      index: rooms.indexWhere((room) => room.key == item.key),
      controller: controller,
      selected: item.key == selectedRoom?.key,
      overlayVisible: _overlay.visible,
      onTap: () => _selectRoomAndFocusControls(item),
      onFocusChanged: (focused) => _onRoomFocusChanged(item, focused),
      onKeyEvent: (key) => _onRoomKeyEvent(item, key),
    );
  }

  Widget _buildTwoRoomLayout(
    List<MultiRoomItem> rooms,
    MultiRoomItem? selectedRoom,
    Size size, {
    required bool mainSub,
  }) {
    final main = mainSub
        ? rooms.firstWhereOrNull(
                (room) => room.key == controller.mainRoomKey.value) ??
            rooms.first
        : rooms.first;
    final other = rooms.firstWhere((room) => room.key != main.key);
    final ratio = mainSub ? 2.0 : 1.0;
    final gap = AppSettingsController.instance.effectiveMultiRoomGap.w;
    final tileWidth = math
        .min(
          math.max(0.0, (size.width - gap * 3) / (ratio + 1)),
          math.max(0.0, size.height - gap * 2) * 16 / 9 / ratio,
        )
        .toDouble();
    final tileHeight = tileWidth * 9 / 16;
    return Center(
      child: SizedBox(
        width: tileWidth * (ratio + 1) + gap,
        height: tileHeight * ratio,
        child: Row(
          children: [
            SizedBox(
              width: tileWidth * ratio,
              height: tileHeight * ratio,
              child: _roomTile(main, rooms, selectedRoom),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: tileWidth,
              height: tileHeight,
              child: _roomTile(other, rooms, selectedRoom),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridLayout(
    List<MultiRoomItem> rooms,
    MultiRoomItem? selectedRoom,
    Size size,
  ) {
    if (rooms.length == 1) return _roomTile(rooms.first, rooms, selectedRoom);
    final gap = AppSettingsController.instance.effectiveMultiRoomGap.w;

    final tileWidth = math
        .min(
          math.max(0.0, (size.width - gap * 3) / 2),
          math.max(0.0, (size.height - gap * 3) / 2) * 16 / 9,
        )
        .toDouble();
    final tileHeight = tileWidth * 9 / 16;
    return Center(
      child: SizedBox(
        width: tileWidth * 2 + gap,
        height: tileHeight * 2 + gap,
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: tileWidth,
                  height: tileHeight,
                  child: _roomTile(rooms[0], rooms, selectedRoom),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: tileWidth,
                  height: tileHeight,
                  child: _roomTile(rooms[1], rooms, selectedRoom),
                ),
              ],
            ),
            SizedBox(height: gap),
            Row(
              children: [
                SizedBox(
                  width: tileWidth,
                  height: tileHeight,
                  child: _roomTile(rooms[2], rooms, selectedRoom),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: tileWidth,
                  height: tileHeight,
                  child: rooms.length > 3
                      ? _roomTile(rooms[3], rooms, selectedRoom)
                      : const SizedBox.expand(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSubLayout(
    List<MultiRoomItem> rooms,
    MultiRoomItem? selectedRoom,
    Size size,
  ) {
    final main = rooms.firstWhereOrNull(
          (room) => room.key == controller.mainRoomKey.value,
        ) ??
        rooms.first;
    final secondary = rooms.where((room) => room.key != main.key).toList();
    final gap = AppSettingsController.instance.effectiveMultiRoomGap.w;
    final widthLimit = math.max(0.0, (size.width - gap) / 4).toDouble();
    final secondaryStackLimit =
        math.max(0.0, size.height - gap * (secondary.length - 1)) /
            (secondary.length * 9 / 16);
    final primaryHeightLimit = math.max(0.0, size.height) / (27 / 16);
    final secondaryWidth = math
        .min(
          widthLimit,
          math.min(secondaryStackLimit, primaryHeightLimit),
        )
        .toDouble();
    final secondaryHeight = secondaryWidth * 9 / 16;
    final primaryWidth = secondaryWidth * 3;
    final primaryHeight = primaryWidth * 9 / 16;
    final secondaryStackHeight =
        secondary.length * secondaryHeight + (secondary.length - 1) * gap;
    final contentHeight =
        math.max(primaryHeight, secondaryStackHeight).toDouble();

    return Center(
      child: SizedBox(
        width: primaryWidth + gap + secondaryWidth,
        height: contentHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: primaryWidth,
              height: primaryHeight,
              child: _roomTile(main, rooms, selectedRoom),
            ),
            SizedBox(width: gap),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < secondary.length; index++) ...[
                  if (index > 0) SizedBox(height: gap),
                  SizedBox(
                    width: secondaryWidth,
                    height: secondaryHeight,
                    child: _roomTile(secondary[index], rooms, selectedRoom),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlay(int roomCount) {
    final settings = AppSettingsController.instance;
    final mainSub = settings.multiRoomLayout.value == 'mainSub';
    final layoutLabel = roomCount == 2
        ? (mainSub ? '切换左右双屏' : '切换主次双屏')
        : (mainSub ? '切换网格布局' : '切换主副布局');
    final nodes = [_addRoomsFocusNode, _layoutFocusNode, _globalMoreFocusNode];

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _overlaySurface(
        key: const ValueKey('multi-room-top-overlay'),
        visible: _overlay.visible,
        alignment: Alignment.topCenter,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xdd000000), Color(0xaa000000), Colors.transparent],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            28.w,
            24.w + MediaQuery.paddingOf(context).top,
            28.w,
            30.w,
          ),
          child: Row(
            children: [
              Icon(Icons.live_tv, color: Colors.white70, size: 26.w),
              SizedBox(width: 12.w),
              Text(
                roomCount == 2 ? '双屏同播  2 路' : '多屏同播  $roomCount 路',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24.w,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _OverlayActionButton(
                key: const ValueKey('multi-room-add'),
                focusNode: _addRoomsFocusNode,
                label: '添加房间',
                icon: Icons.add,
                onPressed: _addRooms,
                onFocusActivity: _overlay.activity,
                onDirection: (key) =>
                    _topDirection(key, _addRoomsFocusNode, nodes),
              ),
              SizedBox(width: 10.w),
              _OverlayActionButton(
                key: const ValueKey('multi-room-layout'),
                focusNode: _layoutFocusNode,
                label: layoutLabel,
                icon: Icons.dashboard_outlined,
                onPressed: roomCount > 1 ? _toggleLayout : null,
                onFocusActivity: _overlay.activity,
                onDirection: (key) =>
                    _topDirection(key, _layoutFocusNode, nodes),
              ),
              SizedBox(width: 10.w),
              _OverlayActionButton(
                key: const ValueKey('multi-room-global-more'),
                focusNode: _globalMoreFocusNode,
                label: '更多',
                icon: Icons.more_horiz,
                onPressed: _showGlobalMore,
                onFocusActivity: _overlay.activity,
                onDirection: (key) =>
                    _topDirection(key, _globalMoreFocusNode, nodes),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay(
    List<MultiRoomItem> rooms,
    MultiRoomItem? selectedRoom,
  ) {
    final selectedIndex = selectedRoom == null
        ? -1
        : rooms.indexWhere((room) => room.key == selectedRoom.key);
    final nodes = [
      _pauseFocusNode,
      _soundFocusNode,
      _danmakuFocusNode,
      _qualityFocusNode,
      _lineFocusNode,
      _roomMoreFocusNode,
    ];
    final player =
        selectedRoom == null ? null : controller.playerFor(selectedRoom);
    final danmakuAvailable =
        selectedRoom != null && controller.isRoomDanmakuAvailable(selectedRoom);
    final danmakuEnabled = selectedRoom != null &&
        controller.isRoomDanmakuEnabled(selectedRoom.key);
    // Capabilities are populated during load; observe its completion so the
    // controls update even when the overlay and selected room stay unchanged.
    final loading = player?.loading.value ?? true;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _overlaySurface(
        key: const ValueKey('multi-room-bottom-overlay'),
        visible: _overlay.visible,
        alignment: Alignment.bottomCenter,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xaa000000), Color(0xdd000000)],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24.w,
            34.w,
            24.w,
            24.w + MediaQuery.paddingOf(context).bottom,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 12.w),
            decoration: BoxDecoration(
              color: const Color(0xe817191c),
              borderRadius: BorderRadius.circular(20.w),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black45, blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: selectedRoom == null || player == null
                ? const SizedBox(height: 64)
                : Row(
                    children: [
                      Expanded(
                        child: _SelectedRoomStatus(
                          key:
                              ValueKey('multi-room-status-${selectedRoom.key}'),
                          item: selectedRoom,
                          index: selectedIndex,
                          player: player,
                        ),
                      ),
                      SizedBox(width: 18.w),
                      _OverlayActionButton(
                        key: const ValueKey('multi-room-pause'),
                        focusNode: _pauseFocusNode,
                        label: player.userPaused.value ? '继续' : '暂停',
                        icon: player.userPaused.value
                            ? Icons.play_arrow
                            : Icons.pause,
                        onPressed: () => player.togglePause(),
                        onFocusActivity: _overlay.activity,
                        onDirection: (key) => _bottomDirection(
                          key,
                          _pauseFocusNode,
                          nodes,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      _OverlayActionButton(
                        key: const ValueKey('multi-room-sound'),
                        focusNode: _soundFocusNode,
                        label: '声音',
                        icon: player.muted.value
                            ? Icons.volume_off
                            : Icons.volume_up,
                        onPressed: () => _showSoundDialog(selectedRoom),
                        onFocusActivity: _overlay.activity,
                        onDirection: (key) => _bottomDirection(
                          key,
                          _soundFocusNode,
                          nodes,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      _OverlayActionButton(
                        key: const ValueKey('multi-room-danmaku'),
                        focusNode: _danmakuFocusNode,
                        label: !danmakuAvailable
                            ? '弹幕不可用'
                            : danmakuEnabled
                                ? '关弹幕'
                                : '开弹幕',
                        icon: !danmakuAvailable
                            ? Icons.block
                            : danmakuEnabled
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                        checked: danmakuAvailable ? danmakuEnabled : null,
                        onPressed: !danmakuAvailable
                            ? null
                            : () => controller.toggleRoomDanmaku(selectedRoom),
                        onFocusActivity: _overlay.activity,
                        onDirection: (key) => _bottomDirection(
                          key,
                          _danmakuFocusNode,
                          nodes,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      _OverlayActionButton(
                        key: const ValueKey('multi-room-quality'),
                        focusNode: _qualityFocusNode,
                        label: '画质',
                        icon: Icons.high_quality_outlined,
                        onPressed: loading || player.qualities.isEmpty
                            ? null
                            : () => _showQualityDialog(selectedRoom),
                        onFocusActivity: _overlay.activity,
                        onDirection: (key) => _bottomDirection(
                          key,
                          _qualityFocusNode,
                          nodes,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      _OverlayActionButton(
                        key: const ValueKey('multi-room-line'),
                        focusNode: _lineFocusNode,
                        label: '线路',
                        icon: Icons.alt_route,
                        onPressed: loading || player.lineCount == 0
                            ? null
                            : () => _showLineDialog(selectedRoom),
                        onFocusActivity: _overlay.activity,
                        onDirection: (key) => _bottomDirection(
                          key,
                          _lineFocusNode,
                          nodes,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      _OverlayActionButton(
                        key: const ValueKey('multi-room-room-more'),
                        focusNode: _roomMoreFocusNode,
                        label: '更多',
                        icon: Icons.more_vert,
                        onPressed: () => _showRoomMore(selectedRoom),
                        onFocusActivity: _overlay.activity,
                        onDirection: (key) => _bottomDirection(
                          key,
                          _roomMoreFocusNode,
                          nodes,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _overlaySurface({
    required Key key,
    required bool visible,
    required Alignment alignment,
    required Gradient gradient,
    required Widget child,
  }) {
    return AnimatedOpacity(
      key: key,
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: Align(
              alignment: alignment,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: gradient),
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _topDirection(
    LogicalKeyboardKey key,
    FocusNode current,
    List<FocusNode> nodes,
  ) {
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusSelectedRoom();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return _moveFocus(
          nodes, current, key == LogicalKeyboardKey.arrowRight ? 1 : -1);
    }
    return false;
  }

  bool _bottomDirection(
    LogicalKeyboardKey key,
    FocusNode current,
    List<FocusNode> nodes,
  ) {
    if (key == LogicalKeyboardKey.arrowUp) {
      _focusSelectedRoom();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return _moveFocus(
          nodes, current, key == LogicalKeyboardKey.arrowRight ? 1 : -1);
    }
    return false;
  }

  bool _moveFocus(List<FocusNode> nodes, FocusNode current, int direction) {
    final index = nodes.indexOf(current);
    if (index < 0) return false;
    final next = (index + direction).clamp(0, nodes.length - 1).toInt();
    nodes[next].requestFocus();
    return true;
  }

  void _onRoomFocusChanged(MultiRoomItem item, bool focused) {
    if (!focused) return;
    controller.focusedRoomKey.value = item.key;
    if (!_suppressFocusActivity && _overlay.visible) _overlay.activity();
  }

  void _selectRoomAndFocusControls(MultiRoomItem item) {
    controller.focusedRoomKey.value = item.key;
    _overlay.activity();
    controller.focusNodeFor(item).requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _overlay.visible &&
          controller.focusedRoomKey.value == item.key) {
        _pauseFocusNode.requestFocus();
      }
    });
  }

  void _focusSelectedRoom() {
    final room = _selectedRoom(controller.rooms.toList(growable: false));
    if (room == null) return;
    controller.focusNodeFor(room).requestFocus();
  }

  void _focusBottomPause() {
    final wasVisible = _overlay.visible;
    _overlay.activity();
    if (wasVisible) {
      _pauseFocusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlay.visible) _pauseFocusNode.requestFocus();
    });
  }

  void _returnFocusBeforeHide() {
    _suppressFocusActivity = true;
    _focusSelectedRoom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressFocusActivity = false;
    });
  }

  KeyEventResult _onRoomKeyEvent(MultiRoomItem item, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (MultiRoomPage._isBackKey(key)) {
      unawaited(_handleBack());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.keyM) {
      _overlay.activity();
      unawaited(_showGlobalMore());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _overlay.activity();
      final rooms = controller.rooms.toList(growable: false);
      if (_isAtTopRoomRow(item, rooms, key)) {
        _addRoomsFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      final target = _nextRoom(item, rooms, key);
      if (target != null) controller.focusNodeFor(target).requestFocus();
      return KeyEventResult.handled;
    }
    if (MultiRoomPage._isActivateKey(key)) {
      if (!_overlay.visible) {
        _focusBottomPause();
      } else {
        final player = controller.playerFor(item);
        if (player.isReleasedForMemory) {
          unawaited(controller.recoverReleasedRoom(item));
        } else if (player.errorText.value.isNotEmpty &&
            player.liveState.value != LiveStatusState.offline) {
          unawaited(controller.refreshRoom(item));
        } else {
          _focusBottomPause();
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isAtTopRoomRow(
    MultiRoomItem item,
    List<MultiRoomItem> rooms,
    LogicalKeyboardKey key,
  ) {
    if (key != LogicalKeyboardKey.arrowUp) return false;
    if (controller.expandedRoomKey.value != null) return true;
    if (AppSettingsController.instance.multiRoomLayout.value == 'mainSub' &&
        rooms.length > 1) {
      final mainIndex =
          rooms.indexWhere((room) => room.key == controller.mainRoomKey.value);
      final secondary = rooms
          .where((room) => room.key != controller.mainRoomKey.value)
          .toList();
      return item.key == controller.mainRoomKey.value ||
          (secondary.isNotEmpty && item.key == secondary.first.key) ||
          mainIndex < 0;
    }
    return rooms.indexWhere((room) => room.key == item.key) < 2;
  }

  MultiRoomItem? _nextRoom(
    MultiRoomItem item,
    List<MultiRoomItem> rooms,
    LogicalKeyboardKey key,
  ) {
    if (rooms.length <= 1 || controller.expandedRoomKey.value != null) {
      return null;
    }
    if (AppSettingsController.instance.multiRoomLayout.value == 'mainSub' &&
        rooms.length > 1) {
      final main = rooms.firstWhereOrNull(
            (room) => room.key == controller.mainRoomKey.value,
          ) ??
          rooms.first;
      final secondary = rooms.where((room) => room.key != main.key).toList();
      if (item.key == main.key && key == LogicalKeyboardKey.arrowRight) {
        return secondary.isEmpty ? null : secondary.first;
      }
      if (item.key != main.key && key == LogicalKeyboardKey.arrowLeft) {
        return main;
      }
      if (item.key != main.key &&
          (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        final index = secondary.indexWhere((room) => room.key == item.key);
        final next = index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1);
        if (next >= 0 && next < secondary.length) return secondary[next];
      }
      return null;
    }
    final currentIndex = rooms.indexWhere((room) => room.key == item.key);
    final targetIndex = MultiRoomFocusPolicy.nextGridIndex(
      currentIndex: currentIndex,
      roomCount: rooms.length,
      columnCount: rooms.length <= 1 ? 1 : 2,
      key: key,
    );
    if (targetIndex == null) return null;
    return rooms[targetIndex];
  }

  Future<void> _handleBack() async {
    if (_overlayHoldCount > 0) {
      await Navigator.of(context, rootNavigator: true).maybePop();
      return;
    }
    if (_overlay.visible) {
      _overlay.hide();
      return;
    }
    await controller.handleBack();
  }

  Future<void> _addRooms() async {
    _overlay.activity();
    final current = controller.rooms.toList(growable: false);
    final selected = await _withOverlayHold<List<MultiRoomItem>>(
      () => showTvRoomPicker(
        maxRooms: controller.roomLimit,
        selectedRooms: current,
        existingRooms: current,
      ),
    );
    if (selected != null) controller.addRooms(selected);
  }

  void _toggleLayout() {
    final settings = AppSettingsController.instance;
    settings.setMultiRoomLayout(
      settings.multiRoomLayout.value == 'mainSub' ? 'grid' : 'mainSub',
    );
  }

  Future<void> _showSettings() async {
    await _withOverlayHold<void>(
      () => Get.dialog<void>(_MultiRoomSettingsDialog(controller)),
    );
  }

  Future<void> _showGlobalMore() async {
    await _withOverlayHold<void>(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _ActionDialog(
            title: '多屏操作',
            actions: [
              _DialogAction(
                label: controller.areAllPaused ? '全部继续' : '全部暂停',
                icon: controller.areAllPaused ? Icons.play_arrow : Icons.pause,
                action: () => controller.toggleAllPause(),
              ),
              _DialogAction(
                label: controller.allMuted.value ? '全部恢复声音' : '全部静音',
                icon: controller.allMuted.value
                    ? Icons.volume_up
                    : Icons.volume_off,
                action: () => controller.toggleAllAudio(),
              ),
              _DialogAction(
                label: '刷新全部',
                icon: Icons.refresh,
                action: () => controller.refreshAll(),
              ),
              _DialogAction(
                label: '多屏设置',
                icon: Icons.tune,
                action: () async {
                  await Future<void>.delayed(Duration.zero);
                  await _showSettings();
                },
              ),
              _DialogAction(
                label: '退出多屏',
                icon: Icons.close,
                action: () => controller.exitPage(),
              ),
            ],
            onSelect: (action) => _closeThen(dialogContext, action.action),
          );
        },
      ),
    );
  }

  Future<void> _showRoomMore(MultiRoomItem item) async {
    final player = controller.playerFor(item);
    await _withOverlayHold<void>(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final actions = <_DialogAction>[
            _DialogAction(
              label: player.isReleasedForMemory ? '恢复资源' : '刷新',
              icon: player.isReleasedForMemory ? Icons.replay : Icons.refresh,
              action: () => player.isReleasedForMemory
                  ? controller.recoverReleasedRoom(item)
                  : controller.refreshRoom(item),
            ),
            _DialogAction(
              label: '设为主画面',
              icon: Icons.star_outline,
              action: () async => controller.setMainRoom(item),
            ),
            _DialogAction(
              label:
                  controller.expandedRoomKey.value == item.key ? '还原布局' : '放大',
              icon: controller.expandedRoomKey.value == item.key
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              action: () => controller.toggleExpanded(item),
            ),
            _DialogAction(
              label: '转为单路播放',
              icon: Icons.open_in_full,
              action: () => _openAsSingleRoom(item),
            ),
            _DialogAction(
              label: '移除房间',
              icon: Icons.close,
              action: () => _removeRoom(item),
            ),
          ];
          return _ActionDialog(
            title:
                '房间 ${controller.rooms.indexWhere((room) => room.key == item.key) + 1} · 更多',
            actions: actions,
            onSelect: (action) => _closeThen(dialogContext, action.action),
          );
        },
      ),
    );
  }

  Future<void> _showSoundDialog(MultiRoomItem item) async {
    final player = controller.playerFor(item);
    await _withOverlayHold<void>(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: const Color(0xff191c20),
          child: SizedBox(
            width: 680,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('声音 · ${item.userName}',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 20),
                  Obx(
                    () => Text(
                      '音量 ${player.volume.value.round()}%  ·  ${player.muted.value ? '静音' : '有声'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 26),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RoomVolumeSlider(
                    player: player,
                    onChanged: (value) => controller.setRoomVolume(item, value),
                    holdOverlay: _overlay.hold,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _OverlayActionButton(
                        label: '音量减',
                        icon: Icons.volume_down,
                        onPressed: () => controller.changeRoomVolume(item, -8),
                      ),
                      const SizedBox(width: 12),
                      _OverlayActionButton(
                        label: '音量加',
                        icon: Icons.volume_up,
                        autofocus: true,
                        onPressed: () => controller.changeRoomVolume(item, 8),
                      ),
                      const SizedBox(width: 12),
                      Obx(
                        () => _OverlayActionButton(
                          label: player.muted.value ? '恢复声音' : '静音',
                          icon: player.muted.value
                              ? Icons.volume_up
                              : Icons.volume_off,
                          onPressed: () => controller.toggleAudio(item),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _OverlayActionButton(
                      label: '完成',
                      icon: Icons.check,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQualityDialog(MultiRoomItem item) async {
    final player = controller.playerFor(item);
    final qualities = player.qualities;
    if (qualities.isEmpty) return;
    final selectedIndex = await _withOverlayHold<int>(
      () => showDialog<int>(
        context: context,
        builder: (dialogContext) => _OptionDialog(
          title: '画质 · ${item.userName}',
          options: [for (final quality in qualities) quality.quality],
          selectedIndex: player.qualityIndex,
          onSelect: (index) => Navigator.of(dialogContext).pop(index),
        ),
      ),
    );
    if (selectedIndex != null) {
      await controller.selectRoomQuality(item, selectedIndex);
    }
  }

  Future<void> _showLineDialog(MultiRoomItem item) async {
    final player = controller.playerFor(item);
    final count = player.lineCount;
    if (count <= 0) return;
    final selectedIndex = await _withOverlayHold<int>(
      () => showDialog<int>(
        context: context,
        builder: (dialogContext) => _OptionDialog(
          title: '线路 · ${item.userName}',
          options: [
            for (var index = 0; index < count; index++) '线路 ${index + 1}'
          ],
          selectedIndex: player.lineIndex,
          onSelect: (index) => Navigator.of(dialogContext).pop(index),
        ),
      ),
    );
    if (selectedIndex != null) {
      await controller.selectRoomLine(item, selectedIndex);
    }
  }

  Future<void> _removeRoom(MultiRoomItem item) async {
    final currentRooms = controller.rooms.toList(growable: false);
    final wasSelected = _selectedRoom(currentRooms)?.key == item.key;
    final nextRoom = currentRooms.firstWhereOrNull(
      (room) => room.key != item.key,
    );
    if (wasSelected && nextRoom != null) {
      controller.focusedRoomKey.value = nextRoom.key;
    }
    await controller.removeRoom(item);
    _tileKeys.remove(item.key);
    if (mounted &&
        wasSelected &&
        nextRoom != null &&
        controller.rooms.any((room) => room.key == nextRoom.key)) {
      controller.focusNodeFor(nextRoom).requestFocus();
    }
  }

  Future<void> _openAsSingleRoom(MultiRoomItem item) async {
    await controller.closePlaybackSession();
    await AppNavigator.toLiveRoomDetail(
      site: item.site,
      roomId: item.roomId,
      douyinSecUserId: item.douyinSecUserId,
      xiaohongshuHostId: item.xiaohongshuHostId,
      replaceCurrentRoute: true,
    );
  }

  Future<T?> _withOverlayHold<T>(Future<T?> Function() action) async {
    final triggerFocus = FocusManager.instance.primaryFocus;
    final release = _overlay.hold();
    _overlayHoldCount++;
    try {
      return await action();
    } finally {
      _overlayHoldCount--;
      release();
      if (mounted &&
          _overlayHoldCount == 0 &&
          _overlay.visible &&
          ModalRoute.of(context)?.isCurrent == true &&
          triggerFocus?.context != null) {
        triggerFocus!.requestFocus();
      }
    }
  }

  void _closeThen(BuildContext dialogContext, Future<void> Function() action) {
    Navigator.of(dialogContext).pop();
    unawaited(action());
  }
}

class _RoomVolumeSlider extends StatefulWidget {
  const _RoomVolumeSlider({
    required this.player,
    required this.onChanged,
    required this.holdOverlay,
  });

  final MultiRoomPlayerController player;
  final Future<void> Function(double) onChanged;
  final VoidCallback Function() holdOverlay;

  @override
  State<_RoomVolumeSlider> createState() => _RoomVolumeSliderState();
}

class _RoomVolumeSliderState extends State<_RoomVolumeSlider> {
  double? _dragValue;
  VoidCallback? _releaseHold;
  int _changeRevision = 0;

  void _releaseDrag() {
    _releaseHold?.call();
    _releaseHold = null;
  }

  @override
  void dispose() {
    _releaseDrag();
    super.dispose();
  }

  Future<void> _setVolume(double value) async {
    final revision = ++_changeRevision;
    await widget.onChanged(value);
    if (mounted && revision == _changeRevision && _releaseHold == null) {
      setState(() => _dragValue = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final volume = widget.player.volume.value;
      return Slider(
        key: const ValueKey('multi-room-volume-slider'),
        value: (_dragValue ?? volume).clamp(0, 100).toDouble(),
        min: 0,
        max: 100,
        divisions: 100,
        label: '${(_dragValue ?? volume).round()}%',
        semanticFormatterCallback: (value) => '音量 ${value.round()}%',
        onChangeStart: (value) {
          _releaseDrag();
          _releaseHold = widget.holdOverlay();
          setState(() => _dragValue = value);
        },
        onChanged: (value) {
          setState(() => _dragValue = value);
          unawaited(_setVolume(value));
        },
        onChangeEnd: (value) {
          _releaseDrag();
          unawaited(_setVolume(value));
        },
      );
    });
  }
}

class _MultiRoomTile extends StatefulWidget {
  const _MultiRoomTile({
    super.key,
    required this.item,
    required this.index,
    required this.controller,
    required this.selected,
    required this.overlayVisible,
    required this.onTap,
    required this.onFocusChanged,
    required this.onKeyEvent,
  });

  final MultiRoomItem item;
  final int index;
  final MultiRoomController controller;
  final bool selected;
  final bool overlayVisible;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChanged;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  State<_MultiRoomTile> createState() => _MultiRoomTileState();
}

class _MultiRoomTileState extends State<_MultiRoomTile> {
  late MultiRoomPlayerController _player =
      widget.controller.playerFor(widget.item);
  late FocusNode _focusNode = widget.controller.focusNodeFor(widget.item);
  late Widget _danmakuView = _createDanmakuView();

  Widget _createDanmakuView() => DanmakuScreen(
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

  @override
  void didUpdateWidget(covariant _MultiRoomTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final player = widget.controller.playerFor(widget.item);
    if (!identical(_player, player)) {
      _player = player;
      _focusNode = widget.controller.focusNodeFor(widget.item);
      _danmakuView = _createDanmakuView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFocusBorder = widget.selected && widget.overlayVisible;
    return KeyedSubtree(
      key: ValueKey('multi-room-tile-${widget.item.key}'),
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: widget.onFocusChanged,
        onKeyEvent: (_, event) => widget.onKeyEvent(event),
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: '第 ${widget.index + 1} 号房间，${widget.item.userName}',
          onTap: widget.onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: const BoxDecoration(color: Colors.black),
              foregroundDecoration: BoxDecoration(
                border: Border.all(
                  color: showFocusBorder
                      ? Colors.lightBlueAccent
                      : Colors.transparent,
                  width: 4.w,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  KeyedSubtree(
                    key: ValueKey('multi-room-video-${widget.item.key}'),
                    child: Obx(() {
                      _player.renderRevision.value;
                      final videoController = _player.videoController;
                      if (videoController == null ||
                          _player.isReleasedForMemory) {
                        return Center(
                          child: Text(
                            _player.isReleasedForMemory ? '资源已释放' : '等待播放器',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 24.w),
                          ),
                        );
                      }
                      return Video(
                        key: ValueKey(
                          '${widget.item.key}-${_player.renderRevision.value}',
                        ),
                        controller: videoController,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      );
                    }),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Obx(() {
                        if (_player.loading.value) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 3),
                          );
                        }
                        if (_player.errorText.value.isNotEmpty) {
                          final isOffline = _player.liveState.value ==
                              LiveStatusState.offline;
                          return _CenterText(
                            _player.errorText.value,
                            action: _player.isReleasedForMemory
                                ? '按确定手动恢复'
                                : isOffline
                                    ? null
                                    : '按确定重试',
                          );
                        }
                        if (_player.liveState.value ==
                            LiveStatusState.offline) {
                          return const _CenterText('未开播');
                        }
                        return const SizedBox.shrink();
                      }),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Obx(
                        () => Offstage(
                          offstage: !_player.showDanmakuState.value,
                          child: _danmakuView,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedRoomStatus extends StatelessWidget {
  const _SelectedRoomStatus({
    super.key,
    required this.item,
    required this.index,
    required this.player,
  });

  final MultiRoomItem item;
  final int index;
  final MultiRoomPlayerController player;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Row(
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: Colors.black,
                fontSize: 22.w,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前操作：${item.site.name} · ${player.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22.w,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3.w),
                Wrap(
                  spacing: 12.w,
                  children: [
                    if (player.qualityDisplayInfo.isNotEmpty)
                      _StatusLabel(player.qualityDisplayInfo),
                    _StatusLabel(
                      player.lineInfo.value.isEmpty
                          ? '线路 —'
                          : player.lineInfo.value,
                    ),
                    _StatusLabel(player.userPaused.value ? '已暂停' : '播放中'),
                    _StatusLabel(
                      player.muted.value
                          ? '静音'
                          : '有声 ${player.volume.value.round()}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white70, fontSize: 15.w),
      );
}

class _OverlayActionButton extends StatefulWidget {
  const _OverlayActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.checked,
    this.onFocusActivity,
    this.onDirection,
  });

  final String label;
  final IconData? icon;
  final FutureOr<void> Function()? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool selected;
  final bool? checked;
  final VoidCallback? onFocusActivity;
  final bool Function(LogicalKeyboardKey key)? onDirection;

  @override
  State<_OverlayActionButton> createState() => _OverlayActionButtonState();
}

class _OverlayActionButtonState extends State<_OverlayActionButton> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: widget.label));

  @override
  void didUpdateWidget(covariant _OverlayActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode && _ownedFocusNode != null) {
      _ownedFocusNode!.dispose();
      _ownedFocusNode = null;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _activate() {
    final action = widget.onPressed;
    if (action == null) return;
    final result = action();
    if (result is Future<void>) unawaited(result);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent) {
      if (MultiRoomPage._isActivateKey(event.logicalKey)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    widget.onFocusActivity?.call();
    if (MultiRoomPage._isActivateKey(event.logicalKey)) {
      _activate();
      return KeyEventResult.handled;
    }
    if (widget.onDirection?.call(event.logicalKey) == true) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final focusNode = _focusNode;
    return Focus(
      focusNode: focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (focused) widget.onFocusActivity?.call();
      },
      onKeyEvent: _onKeyEvent,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: widget.selected,
        checked: widget.checked,
        inMutuallyExclusiveGroup: widget.checked != null,
        label: widget.label,
        onTap: enabled ? _activate : null,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _activate : null,
            child: AnimatedBuilder(
              animation: focusNode,
              builder: (context, _) {
                final focused = focusNode.hasFocus;
                final highlighted = focused || widget.selected;
                return Container(
                  constraints: BoxConstraints(
                    minHeight: math.max(58.w, 48).toDouble(),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(16.w, 12).toDouble(),
                    vertical: 8.w,
                  ),
                  decoration: BoxDecoration(
                    color: !enabled
                        ? Colors.white.withAlpha(12)
                        : highlighted
                            ? const Color(0xffdff4ff)
                            : Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(14.w),
                    border: Border.all(
                      color: focused ? Colors.lightBlueAccent : Colors.white24,
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: math.max(22.w, 18).toDouble(),
                          color: enabled && highlighted
                              ? Colors.black
                              : Colors.white,
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: enabled && highlighted
                              ? Colors.black
                              : Colors.white,
                          fontSize: math.max(17.w, 14).toDouble(),
                          fontWeight:
                              focused ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (widget.checked == true) ...[
                        SizedBox(width: 8.w),
                        Icon(Icons.check, size: 20.w, color: Colors.black),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogAction {
  const _DialogAction({required this.label, required this.action, this.icon});

  final String label;
  final IconData? icon;
  final Future<void> Function() action;
}

class _ActionDialog extends StatelessWidget {
  const _ActionDialog({
    required this.title,
    required this.actions,
    required this.onSelect,
  });

  final String title;
  final List<_DialogAction> actions;
  final ValueChanged<_DialogAction> onSelect;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff191c20),
      child: SizedBox(
        width: 640,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _OverlayActionButton(
                  key: ValueKey('multi-room-menu-${actions[index].label}'),
                  label: actions[index].label,
                  icon: actions[index].icon,
                  autofocus: index == 0,
                  onPressed: () => onSelect(actions[index]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionDialog extends StatelessWidget {
  const _OptionDialog({
    required this.title,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String title;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final height = math.min(600.0, 130 + options.length * 70.0);
    return Dialog(
      backgroundColor: const Color(0xff191c20),
      child: SizedBox(
        width: 620,
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final isSelected = index == selectedIndex;
                    return _OverlayActionButton(
                      label: options[index],
                      icon: Icons.radio_button_checked,
                      checked: isSelected,
                      selected: isSelected,
                      autofocus:
                          isSelected || (selectedIndex < 0 && index == 0),
                      onPressed: () => onSelect(index),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _OverlayActionButton(
                  label: '取消',
                  icon: Icons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
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
          borderRadius: BorderRadius.circular(12.w),
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
              Text(
                action!,
                style: TextStyle(color: Colors.white60, fontSize: 16.w),
              ),
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
      backgroundColor: const Color(0xff191c20),
      child: SizedBox(
        width: 620,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '多屏设置',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
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
                child: _OverlayActionButton(
                  autofocus: true,
                  label: '完成',
                  icon: Icons.check,
                  onPressed: Get.back<void>,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
