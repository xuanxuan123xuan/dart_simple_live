import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

class _Probe with PlayerMixin {
  bool closing = false;
  int reconciliations = 0;
  @override
  bool get recordingPlayerClosing => closing;
  @override
  void onRecordingNativeMutationSettled(String? deferredError) {
    reconciliations++;
  }
}

void main() {
  testWidgets('caller timeout does not release an unfinished native mutation',
      (tester) async {
    final owner = _Probe();
    final nativeReply = Completer<void>();
    final operation =
        owner.runRecordingNativeMutation(() => nativeReply.future);
    final timedOut = expectLater(operation.timeout(const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 2));
    await timedOut;
    expect(owner.recordingNativeMutationQuiet, isTrue);
    expect(owner.reconciliations, 0);
    nativeReply.complete();
    await tester.pump();
    await operation;
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.recordingNativeMutationQuiet, isFalse);
    expect(owner.reconciliations, 1);
  });

  testWidgets(
      'overlapping native mutations reconcile only after the last reply',
      (tester) async {
    final owner = _Probe();
    final first = Completer<void>(), second = Completer<void>();
    final operations = [
      owner.runRecordingNativeMutation(() => first.future),
      owner.runRecordingNativeMutation(() => second.future)
    ];
    first.complete();
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.recordingNativeMutationQuiet, isTrue);
    expect(owner.reconciliations, 0);
    second.complete();
    await tester.pump();
    await Future.wait(operations);
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.reconciliations, 1);
  });

  testWidgets('closing owner suppresses deferred playback recovery',
      (tester) async {
    final owner = _Probe();
    final reply = Completer<void>();
    final operation = owner.runRecordingNativeMutation(() => reply.future);
    owner.closing = true;
    reply.complete();
    await tester.pump();
    await operation;
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.recordingNativeMutationQuiet, isFalse);
    expect(owner.reconciliations, 0);
  });
  testWidgets('next mutation cancels the previous delayed reconciliation',
      (tester) async {
    final owner = _Probe();
    await owner.runRecordingNativeMutation(() async {});
    await tester.pump(const Duration(milliseconds: 50));
    final next = Completer<void>();
    final operation = owner.runRecordingNativeMutation(() => next.future);
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.recordingNativeMutationQuiet, isTrue);
    expect(owner.reconciliations, 0);
    next.complete();
    await tester.pump();
    await operation;
    await tester.pump(const Duration(milliseconds: 200));
    expect(owner.recordingNativeMutationQuiet, isFalse);
    expect(owner.reconciliations, 1);
  });
}
