import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/player_resource_lifecycle.dart';
import 'package:simple_live_app/widgets/player_view_gate.dart';

void main() {
  test('native opens are serialized and stale opens do not run', () async {
    final queue = PlayerNativeOpenQueue();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var current = true;
    var secondRan = false;

    final first = queue.open(
      operation: () async {
        firstStarted.complete();
        await releaseFirst.future;
      },
      isCurrent: () => current,
      timeout: const Duration(seconds: 1),
      onPreviousError: (_, __) {},
    );
    await firstStarted.future;
    final second = queue.open(
      operation: () async => secondRan = true,
      isCurrent: () => current,
      timeout: const Duration(seconds: 1),
      onPreviousError: (_, __) {},
    );
    current = false;
    releaseFirst.complete();

    expect(await first, PlayerOpenStatus.stale);
    expect(await second, PlayerOpenStatus.stale);
    expect(secondRan, isFalse);
  });

  test('a timed out open keeps ownership until the native future settles', () async {
    final queue = PlayerNativeOpenQueue();
    final started = Completer<void>();
    final release = Completer<void>();
    var secondRan = false;

    final first = queue.open(
      operation: () async {
        started.complete();
        await release.future;
      },
      isCurrent: () => true,
      timeout: const Duration(milliseconds: 10),
      onPreviousError: (_, __) {},
    );
    await started.future;
    expect(await first, PlayerOpenStatus.timedOut);
    expect(queue.hasInflight, isTrue);

    final second = queue.open(
      operation: () async => secondRan = true,
      isCurrent: () => true,
      timeout: const Duration(milliseconds: 10),
      onPreviousError: (_, __) {},
    );
    expect(await second, PlayerOpenStatus.timedOut);
    expect(secondRan, isFalse);

    release.complete();
    await queue.waitUntilIdle();
    expect(queue.hasInflight, isFalse);
    expect(
      await queue.open(
        operation: () async => secondRan = true,
        isCurrent: () => true,
        timeout: const Duration(seconds: 1),
        onPreviousError: (_, __) {},
      ),
      PlayerOpenStatus.opened,
    );
    expect(secondRan, isTrue);
  });

  test('retirement waits for real release and reports failures', () async {
    final coordinator = PlayerRetirementCoordinator();
    final release = Completer<void>();
    coordinator.retire(1, release.future);
    expect(coordinator.pendingCount, 1);
    expect(
      await coordinator.waitUntilReleased(
        instanceId: 2,
        timeout: const Duration(milliseconds: 10),
      ),
      PlayerHandoffStatus.timedOut,
    );
    release.complete();
    expect(
      await coordinator.waitUntilReleased(
        instanceId: 2,
        timeout: const Duration(seconds: 1),
      ),
      PlayerHandoffStatus.ready,
    );

    final failed = Completer<void>();
    coordinator.retire(3, failed.future);
    failed.completeError(StateError('release failed'));
    await Future<void>.delayed(Duration.zero);
    expect(
      await coordinator.waitUntilReleased(
        instanceId: 2,
        timeout: const Duration(seconds: 1),
      ),
      PlayerHandoffStatus.releaseFailed,
    );
  });

  test('cleanup reaches dispose after an earlier step fails', () async {
    final errors = <String>[];
    var disposed = false;
    await releasePlayerResources(
      steps: [
        PlayerCleanupStep('stop', () => throw StateError('stop failed')),
      ],
      dispose: () async => disposed = true,
      onError: (name, _, __) => errors.add(name),
    );
    expect(errors, ['stop']);
    expect(disposed, isTrue);
  });

  test('cleanup barrier failure prevents native dispose', () async {
    var disposed = false;
    final errors = <String>[];
    await releasePlayerResources(
      steps: const [],
      beforeDispose: () => Future<void>.error(StateError('recording busy')),
      dispose: () async => disposed = true,
      onError: (name, _, __) => errors.add(name),
    );
    expect(errors, ['beforeDispose']);
    expect(disposed, isFalse);
  });

  test('registered owner blocks handoff until its retirement completes', () async {
    final coordinator = PlayerRetirementCoordinator();
    final oldId = coordinator.register();
    final newId = coordinator.register();
    final release = Completer<void>();
    coordinator.retire(oldId, release.future);

    final waiting = coordinator.waitUntilReleased(
      instanceId: newId,
      timeout: const Duration(seconds: 1),
    );
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.pendingCount, 2);
    release.complete();
    expect(await waiting, PlayerHandoffStatus.ready);
    expect(coordinator.pendingCount, 1);
  });

  testWidgets('player view gate does not build native content early',
      (tester) async {
    var nativeBuilt = false;
    await tester.pumpWidget(
      PlayerViewGate(
        ready: false,
        readyBuilder: (_) {
          nativeBuilt = true;
          return const SizedBox(key: ValueKey('native'));
        },
        waitingBuilder: (_) => const SizedBox(key: ValueKey('waiting')),
      ),
    );
    expect(nativeBuilt, isFalse);
    expect(find.byKey(const ValueKey('waiting')), findsOneWidget);
  });
}
