import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_hold_preview_layout.dart';

void main() {
  test('portrait preview is centered over the player and keeps 16:9', () {
    final rect = resolveLiveRoomHoldPreviewRect(
      screenSize: const Size(390, 844),
      safePadding: const EdgeInsets.fromLTRB(0, 47, 0, 34),
      playerRect: const Rect.fromLTWH(0, 47, 390, 300),
      portrait: true,
    );

    expect(rect.width, closeTo(241.8, 0.001));
    expect(rect.height / rect.width, closeTo(9 / 16, 0.0001));
    expect(rect.center.dx, closeTo(195, 0.001));
    expect(rect.top, greaterThanOrEqualTo(47));
  });

  test('landscape preview stays left of an active right panel', () {
    final rect = resolveLiveRoomHoldPreviewRect(
      screenSize: const Size(1194, 834),
      safePadding: const EdgeInsets.fromLTRB(24, 0, 20, 20),
      playerRect: const Rect.fromLTWH(24, 0, 1150, 814),
      portrait: false,
      obscuredRight: 400,
    );

    expect(rect.width, inInclusiveRange(260, 420));
    expect(rect.right, lessThanOrEqualTo(774 - 12));
    expect(rect.height / rect.width, closeTo(9 / 16, 0.0001));
  });

  test('small split view constrains preview inside the safe player area', () {
    final rect = resolveLiveRoomHoldPreviewRect(
      screenSize: const Size(320, 640),
      safePadding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
      playerRect: const Rect.fromLTWH(0, 0, 320, 200),
      portrait: true,
    );

    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(312));
    expect(rect.top, greaterThanOrEqualTo(20));
    expect(rect.bottom, lessThanOrEqualTo(200));
  });
}
