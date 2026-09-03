import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';

typedef FocusOnKeyDownCallback = KeyEventResult Function();

/// 高亮组件
class HighlightWidget extends StatefulWidget {
  final AppFocusNode focusNode;
  final Widget child;
  final FocusOnKeyDownCallback? onUpKey;
  final FocusOnKeyDownCallback? onDownKey;
  final FocusOnKeyDownCallback? onLeftKey;
  final FocusOnKeyDownCallback? onRightKey;
  final Function(bool)? onFocusChange;
  final Function()? onTap;
  final Function()? onLongPress;
  final Color foucsedColor;
  final Color color;
  final bool autofocus;
  final BorderRadius? borderRadius;
  final double order;
  final bool selected;
  final Duration longPressDuration;
  const HighlightWidget({
    required this.focusNode,
    required this.child,
    this.onUpKey,
    this.onDownKey,
    this.onLeftKey,
    this.onRightKey,
    this.onFocusChange,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.selected = false,
    this.borderRadius,
    this.order = 0.0,
    this.color = Colors.transparent,
    this.foucsedColor = Colors.white,
    this.longPressDuration = const Duration(milliseconds: 600),
    Key? key,
  }) : super(key: key);

  @override
  State<HighlightWidget> createState() => _HighlightWidgetState();
}

class _HighlightWidgetState extends State<HighlightWidget> {
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _activationKeyDownSeen = false;

  bool _isActivationKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  KeyEventResult _handleActivationKey(KeyEvent event) {
    if (widget.onLongPress == null) {
      if (event is KeyDownEvent) {
        _activationKeyDownSeen = true;
        if (widget.onTap == null) return KeyEventResult.ignored;
        widget.onTap!.call();
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _activationKeyDownSeen = false;
      }
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _cancelLongPress();
      _activationKeyDownSeen = true;
      _longPressTriggered = false;
      _longPressTimer = Timer(widget.longPressDuration, () {
        _longPressTimer = null;
        _longPressTriggered = true;
        widget.onLongPress?.call();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _cancelLongPress();
      final shouldTap = _activationKeyDownSeen && !_longPressTriggered;
      _activationKeyDownSeen = false;
      _longPressTriggered = false;
      if (shouldTap) {
        widget.onTap?.call();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _cancelLongPress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          if (!focused) {
            _cancelLongPress();
            _longPressTriggered = false;
            _activationKeyDownSeen = false;
          }
          widget.onFocusChange?.call(focused);
        },
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent) {
            if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
              return widget.onRightKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
              return widget.onLeftKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
              return widget.onUpKey?.call() ?? KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
              return widget.onDownKey?.call() ?? KeyEventResult.ignored;
            }
          }
          if (_isActivationKey(e.logicalKey)) {
            return _handleActivationKey(e);
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Obx(
            () => AnimatedScale(
              scale: widget.focusNode.isFoucsed.value ? 1.06 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  boxShadow: widget.focusNode.isFoucsed.value
                      ? AppStyle.highlightShadow
                      : null,
                  color: (widget.focusNode.isFoucsed.value || widget.selected)
                      ? widget.foucsedColor
                      : widget.color,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
