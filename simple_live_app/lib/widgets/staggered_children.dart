import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 逐帧 reveal 子项的容器。
///
/// 鸿蒙（flutter_ohos）等平台上，一次 build 出大量设置项（20+ 开关/滑条/
/// 菜单 + 各自 Obx）会让页面打开瞬间首帧明显卡顿。该组件首帧只构建
/// 前 [initialCount] 个子项，之后每个 frame 回调再 reveal [step] 个，
/// 页面快速"填充"出来，避免一次性全量构建。
///
/// 用法：替代 `Column(children: [...])`，行为等价（垂直排列、stretch），
/// 仅把 children 分批构建。交互（开关切换等）不受影响。
class StaggeredChildren extends StatefulWidget {
  const StaggeredChildren({
    required this.children,
    this.initialCount = 3,
    this.step = 2,
    super.key,
  });

  final List<Widget> children;
  final int initialCount;
  final int step;

  @override
  State<StaggeredChildren> createState() => _StaggeredChildrenState();
}

class _StaggeredChildrenState extends State<StaggeredChildren> {
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = math.min(widget.initialCount, widget.children.length);
    if (_count < widget.children.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealMore());
    }
  }

  void _revealMore() {
    if (!mounted || _count >= widget.children.length) {
      return;
    }
    setState(() {
      _count = math.min(_count + widget.step, widget.children.length);
    });
    if (_count < widget.children.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.children.take(_count).toList(),
    );
  }
}
