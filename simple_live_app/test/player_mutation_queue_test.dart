import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/player_mutation_queue.dart';

void main() {
  test('serializes operations and reports pending work', () async {
    final queue = PlayerMutationQueue();
    final firstGate = Completer<void>();
    final events = <String>[];

    final first = queue.run(() async {
      events.add('first-start');
      await firstGate.future;
      events.add('first-end');
    });
    final second = queue.run(() async {
      events.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    expect(queue.pendingCount, 2);

    firstGate.complete();
    await Future.wait([first, second]);
    expect(events, ['first-start', 'first-end', 'second']);
    expect(queue.pendingCount, 0);
  });

  test('a failed operation does not poison later work', () async {
    final queue = PlayerMutationQueue();
    final failed = queue.run<void>(() async => throw StateError('failed'));
    final succeeded = queue.run(() async => 42);

    await expectLater(failed, throwsStateError);
    expect(await succeeded, 42);
    await queue.idle;
  });

  test('close rejects new work after draining queued work', () async {
    final queue = PlayerMutationQueue();
    final gate = Completer<void>();
    final pending = queue.run(() => gate.future);
    final closing = queue.close();

    await expectLater(
      queue.run<void>(() async {}),
      throwsStateError,
    );
    gate.complete();
    await pending;
    await closing;
  });
}
