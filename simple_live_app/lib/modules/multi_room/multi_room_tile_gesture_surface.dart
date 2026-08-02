import 'package:flutter/material.dart';

/// Coordinates the gestures that belong to one tile in the multi-room page.
///
/// Keeping the single and double tap recognizers on the same gesture detector
/// lets Flutter suppress the single-tap callbacks when a double tap wins. A
/// descendant button or long-press draggable can still win the gesture arena
/// without toggling either set of controls.
class MultiRoomTileGestureSurface extends StatelessWidget {
  const MultiRoomTileGestureSurface({
    super.key,
    required this.onTogglePageOverlay,
    required this.onToggleTileControls,
    required this.onDoubleTap,
    required this.child,
  });

  final VoidCallback onTogglePageOverlay;
  final VoidCallback onToggleTileControls;
  final VoidCallback onDoubleTap;
  final Widget child;

  void _handleTap() {
    onTogglePageOverlay();
    onToggleTileControls();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _handleTap,
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}
