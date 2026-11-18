import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/playback_display_coordinator.dart';

void main() {
  test('iOS lets FlutterViewController own status bar visibility', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      infoPlist,
      matches(
        RegExp(
          r'<key>UIViewControllerBasedStatusBarAppearance</key>\s*<true/>',
        ),
      ),
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('aggregates wakelock and gives system UI to the newest active lease',
      () async {
    final gateway = _FakePlaybackDisplayGateway();
    final coordinator = PlaybackDisplayCoordinator(gateway: gateway);
    await coordinator.initialize();
    gateway.clear();

    final room = coordinator.acquire(
      debugLabel: 'room',
      keepScreenAwake: true,
      immersiveSystemUi: true,
    );
    await coordinator.settle();
    expect(gateway.keepAwakeCalls, [true]);
    expect(gateway.immersiveCalls, [true]);

    final dialog = coordinator.acquire(
      debugLabel: 'dialog',
      immersiveSystemUi: false,
    );
    await coordinator.settle();
    expect(gateway.keepAwakeCalls, [true]);
    expect(gateway.immersiveCalls, [true, false]);

    dialog.dispose();
    await coordinator.settle();
    expect(gateway.immersiveCalls, [true, false, true]);

    room.dispose();
    await coordinator.settle();
    expect(gateway.keepAwakeCalls, [true, false]);
    expect(gateway.immersiveCalls, [true, false, true, false]);
    coordinator.onClose();
  });

  test('serializes platform writes and corrects a stale request', () async {
    final immersiveGate = Completer<void>();
    final gateway = _FakePlaybackDisplayGateway(
      blockFirstImmersiveEnable: immersiveGate.future,
    );
    final coordinator = PlaybackDisplayCoordinator(gateway: gateway);
    await coordinator.initialize();
    gateway.clear();

    coordinator.acquire(immersiveSystemUi: true);
    await Future<void>.delayed(Duration.zero);
    coordinator.acquire(immersiveSystemUi: false);
    immersiveGate.complete();
    await coordinator.settle();

    expect(gateway.immersiveCalls, [true, false]);
    expect(gateway.maxConcurrentCalls, 1);
    coordinator.onClose();
  });

  test('disables in background and restores after the first foreground frame',
      () async {
    VoidCallback? foregroundFrame;
    final gateway = _FakePlaybackDisplayGateway();
    final coordinator = PlaybackDisplayCoordinator(
      gateway: gateway,
      scheduleAfterFrame: (callback) => foregroundFrame = callback,
    );
    await coordinator.initialize();
    final lease = coordinator.acquire(
      keepScreenAwake: true,
      immersiveSystemUi: true,
    );
    await coordinator.settle();
    gateway.clear();

    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    await coordinator.settle();
    expect(gateway.keepAwakeCalls, [false]);
    expect(gateway.immersiveCalls, [false]);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    // Lease updates while a foreground frame is pending must not cancel the
    // lifecycle restore.
    lease.setKeepScreenAwake(false);
    lease.setKeepScreenAwake(true);
    await coordinator.settle();
    expect(gateway.keepAwakeCalls, [false]);
    expect(gateway.immersiveCalls, [false]);

    foregroundFrame!();
    await coordinator.settle();
    expect(gateway.keepAwakeCalls, [false, true]);
    expect(gateway.immersiveCalls, [false, true]);

    lease.dispose();
    await coordinator.settle();
    coordinator.onClose();
  });

  test('drops a stale delayed iOS immersive recheck', () async {
    final recheckGate = Completer<void>();
    final gateway = _FakePlaybackDisplayGateway(requiresRecheck: true);
    final coordinator = PlaybackDisplayCoordinator(
      gateway: gateway,
      delay: (_) => recheckGate.future,
    );
    await coordinator.initialize();
    gateway.clear();

    final lease = coordinator.acquire(immersiveSystemUi: true);
    await Future<void>.delayed(Duration.zero);
    lease.setImmersiveSystemUi(false);
    recheckGate.complete();
    await coordinator.settle();

    expect(gateway.immersiveCalls, [true, false]);
    lease.dispose();
    await coordinator.settle();
    coordinator.onClose();
  });

  test('reapplies immersive after metrics change (iPad rotation)', () async {
    final gateway = _FakePlaybackDisplayGateway(requiresRecheck: true);
    final coordinator = PlaybackDisplayCoordinator(
      gateway: gateway,
      metricsDebounceDuration: const Duration(milliseconds: 20),
    );
    await coordinator.initialize();
    final lease = coordinator.acquire(immersiveSystemUi: true);
    await coordinator.settle();
    gateway.clear();

    // 旋转/尺寸变化后 UIKit 可能重置状态栏外观，应强制重新应用。
    // （首次为强制重应用，随后是 drain 内 requiresImmersiveRecheck 的
    //  120ms 二次重检，均为幂等的 true。）
    coordinator.didChangeMetrics();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await coordinator.settle();
    expect(gateway.immersiveCalls, [true, true]);

    lease.dispose();
    await coordinator.settle();
    coordinator.onClose();
  });
}

class _FakePlaybackDisplayGateway implements PlaybackDisplayGateway {
  _FakePlaybackDisplayGateway({
    this.requiresRecheck = false,
    this.blockFirstImmersiveEnable,
  });

  final bool requiresRecheck;
  final Future<void>? blockFirstImmersiveEnable;
  final List<bool> keepAwakeCalls = [];
  final List<bool> immersiveCalls = [];
  int concurrentCalls = 0;
  int maxConcurrentCalls = 0;
  bool _blockedImmersiveEnable = false;

  @override
  bool get requiresImmersiveRecheck => requiresRecheck;

  @override
  Future<void> setKeepScreenAwake(bool enabled) async {
    await _recordCall(() async {
      keepAwakeCalls.add(enabled);
    });
  }

  @override
  Future<void> setImmersiveSystemUi(bool immersive) async {
    await _recordCall(() async {
      immersiveCalls.add(immersive);
      if (immersive &&
          !_blockedImmersiveEnable &&
          blockFirstImmersiveEnable != null) {
        _blockedImmersiveEnable = true;
        await blockFirstImmersiveEnable;
      }
    });
  }

  Future<void> _recordCall(Future<void> Function() operation) async {
    concurrentCalls += 1;
    if (concurrentCalls > maxConcurrentCalls) {
      maxConcurrentCalls = concurrentCalls;
    }
    try {
      await operation();
    } finally {
      concurrentCalls -= 1;
    }
  }

  void clear() {
    keepAwakeCalls.clear();
    immersiveCalls.clear();
    concurrentCalls = 0;
    maxConcurrentCalls = 0;
  }
}
