import 'dart:async';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

/// 协调器测试：fake clock + 可计数 task，验证合并、缓存、最小间隔、
/// 优先级与冷却行为，不依赖真实网络。
void main() {
  group('KuaishouRequestCoordinator 同 key in-flight 合并', () {
    test('并发同 key 请求只执行一次 task，其他调用复用同一 Future', () async {
      final coordinator = KuaishouRequestCoordinator();
      var calls = 0;
      final barrier = Completer<String>();

      Future<String> task() {
        calls += 1;
        return barrier.future;
      }

      final first = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'room_detail:1',
        task: task,
      );
      final second = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'room_detail:1',
        task: task,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 1, reason: '同 key 在途请求应合并为一次执行');

      barrier.complete('ok');
      expect(await first, 'ok');
      expect(await second, 'ok');
    });

    test('同 key 在队列中等待时也只保留一个请求', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      final firstGate = Completer<void>();
      var firstCalls = 0;
      var secondCalls = 0;

      final first = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'room_detail:first',
        task: () async {
          firstCalls += 1;
          await firstGate.future;
          return 'first';
        },
      );
      final queued = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'room_detail:queued',
        task: () async {
          secondCalls += 1;
          return 'queued';
        },
      );
      final merged = coordinator.schedule(
        priority: KuaishouRequestPriority.followRefresh,
        key: 'room_detail:queued',
        task: () async {
          secondCalls += 100;
          return 'wrong';
        },
      );

      firstGate.complete();
      expect(await first, 'first');
      expect(await queued, 'queued');
      expect(await merged, 'queued');
      expect(firstCalls, 1);
      expect(secondCalls, 1, reason: '排队阶段的同 key 请求不得重复发出');
    });
  });

  group('KuaishouRequestCoordinator 短 TTL 缓存', () {
    test('TTL 内缓存命中不再执行 task；失败结果不缓存', () async {
      final coordinator = KuaishouRequestCoordinator();
      var successCalls = 0;
      var failCalls = 0;

      Future<String> successTask() async {
        successCalls += 1;
        return 'detail';
      }

      Future<String> failTask() async {
        failCalls += 1;
        throw StateError('fail');
      }

      final first = await coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'room_detail:cache',
        cacheTtl: const Duration(seconds: 15),
        task: successTask,
      );
      expect(first, 'detail');
      expect(successCalls, 1);

      final second = await coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'room_detail:cache',
        cacheTtl: const Duration(seconds: 15),
        task: successTask,
      );
      expect(second, 'detail');
      expect(successCalls, 1, reason: 'TTL 内应命中缓存，不再执行 task');

      // 失败不缓存：再次执行应重新跑 task 并再次失败。
      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'room_detail:fail',
          cacheTtl: const Duration(seconds: 15),
          task: failTask,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'room_detail:fail',
          cacheTtl: const Duration(seconds: 15),
          task: failTask,
        ),
        throwsA(isA<StateError>()),
      );
      expect(failCalls, 2, reason: '失败结果不应缓存');
    });
  });

  group('KuaishouRequestCoordinator 最小间隔', () {
    test('后台请求之间受最小间隔约束', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: const Duration(milliseconds: 120),
        maxJitter: Duration.zero,
      );
      final starts = <int>[];

      Future<String> task(String name) async {
        starts.add(DateTime.now().millisecondsSinceEpoch);
        return name;
      }

      final results = await Future.wait([
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'a',
          task: () => task('a'),
        ),
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'b',
          task: () => task('b'),
        ),
      ]);
      expect(results, ['a', 'b']);
      expect(starts.length, 2);
      final gap = starts[1] - starts[0];
      expect(gap, greaterThanOrEqualTo(120),
          reason: '后台请求应至少间隔 minInterval(120ms)，实际 $gap ms');
    });

    test('多个后台请求同轮排队时彼此仍保持最小间隔（串行不并发）', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: const Duration(milliseconds: 80),
        maxJitter: Duration.zero,
      );
      final starts = <int>[];
      var active = 0;
      var maxActive = 0;

      Future<String> task(String name) async {
        active += 1;
        maxActive = active > maxActive ? active : maxActive;
        starts.add(DateTime.now().millisecondsSinceEpoch);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        active -= 1;
        return name;
      }

      // 3 个后台请求连续入队：串行执行，任意时刻最多 1 个在跑。
      final results = await Future.wait([
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'a',
          task: () => task('a'),
        ),
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'b',
          task: () => task('b'),
        ),
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'c',
          task: () => task('c'),
        ),
      ]);
      expect(results, ['a', 'b', 'c']);
      expect(maxActive, 1, reason: '后台敏感请求必须串行，不得并发');
      expect(starts.length, 3);
      for (var i = 1; i < starts.length; i++) {
        final gap = starts[i] - starts[i - 1];
        expect(gap, greaterThanOrEqualTo(80),
            reason: '同轮排队的后台请求之间也应保持 minInterval，实际 gap=$gap ms');
      }
    });
  });

  group('KuaishouRequestCoordinator 优先级', () {
    test('用户主动进房插队：不受最小间隔约束，先于排队中的后台请求执行', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: const Duration(milliseconds: 200),
        maxJitter: Duration.zero,
      );
      final order = <String>[];

      // 先入队两个后台请求（会因最小间隔被节流）。
      final follow = coordinator.schedule(
        priority: KuaishouRequestPriority.followRefresh,
        key: 'follow',
        task: () async {
          order.add('follow');
          return 'follow';
        },
      );
      final status = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'status',
        task: () async {
          order.add('status');
          return 'status';
        },
      );
      // 用户主动进房：应绕过最小间隔立即执行，不被后台请求阻塞。
      final enter = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'enter',
        task: () async {
          order.add('enter');
          return 'enter';
        },
      );

      final results = await Future.wait([follow, status, enter]);
      expect(results, ['follow', 'status', 'enter']);
      expect(order.contains('enter'), isTrue);
      expect(order.first, 'follow');
      // userEnter 不受最小间隔约束：其在队列中时不会排在后台请求之后等待。
      // 由于 follow 先出队执行，enter 应紧随其后（跳过 status 的间隔等待）。
      expect(order.indexOf('enter'), lessThanOrEqualTo(1));
    });
  });

  group('KuaishouRequestCoordinator 冷却', () {
    test('冷却期内后台请求被拒绝，用户主动进房放行', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      coordinator.beginCooldown(const Duration(minutes: 10));

      // 后台请求应直接失败。
      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'background',
          task: () async => 'ok',
        ),
        throwsA(isA<KuaishouCooldownError>()),
      );

      // 用户主动进房应放行（单探针）。
      final gate = Completer<String>();
      final enterResult = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'enter',
        task: () => gate.future,
      );
      // 探针额度覆盖整个冷却窗口，而不只是一次请求的在途时间。
      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'second-enter',
          task: () async => 'should-not-run',
        ),
        throwsA(isA<KuaishouCooldownError>()),
      );
      gate.complete('entered');
      expect(await enterResult, 'entered');
      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'third-enter',
          task: () async => 'should-not-run',
        ),
        throwsA(isA<KuaishouCooldownError>()),
      );

      // 结束冷却后后台请求恢复。
      coordinator.endCooldown();
      final after = await coordinator.schedule(
        priority: KuaishouRequestPriority.followRefresh,
        key: 'after',
        task: () async => 'ok',
      );
      expect(after, 'ok');
    });

    test('reset during interval wait prevents stale queued task from executing',
        () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: const Duration(milliseconds: 200),
        maxJitter: Duration.zero,
      );
      final first = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'first',
        task: () async => 'first',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var staleCalls = 0;
      final stale = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'stale',
        task: () async {
          staleCalls += 1;
          return 'stale';
        },
      );
      final staleExpectation = expectLater(
        stale,
        throwsA(isA<KuaishouCooldownError>()),
      );
      await first;
      coordinator.reset();
      await staleExpectation;
      expect(staleCalls, 0, reason: 'reset 后旧节流请求不得再发网络请求');
    });

    test('reset 清空队列与在途状态', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      coordinator.beginCooldown(const Duration(minutes: 1));
      coordinator.reset();
      expect(coordinator.inCooldown, isFalse);
      expect(coordinator.queuedCount, 0);
      expect(coordinator.inFlightCount, 0);
    });

    test('beginCooldown 取更长剩余时长，短冷却不覆盖长冷却', () async {
      var fakeNow = DateTime(2026, 1, 1);
      final coordinator = KuaishouRequestCoordinator(
        nowProvider: () => fakeNow,
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );

      coordinator.beginCooldown(const Duration(minutes: 5));
      // 5 分钟后（仍处于 5min 冷却内）再来一个 2min 冷却：不应缩短。
      fakeNow = fakeNow.add(const Duration(minutes: 3));
      coordinator.beginCooldown(const Duration(minutes: 2));
      // 距 5min 冷却结束还有 2min，仍应处于冷却中。
      fakeNow = fakeNow.add(const Duration(minutes: 1));
      expect(coordinator.inCooldown, isTrue, reason: '短冷却不应覆盖更长剩余时长');
      // 5min 冷却到期后退出。
      fakeNow = fakeNow.add(const Duration(minutes: 2));
      expect(coordinator.inCooldown, isFalse);
    });

    test('reset 时在途请求完成不污染新会话，等待者收到重置错误', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      final gate = Completer<String>();

      final pending = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'room_detail:old',
        cacheTtl: const Duration(seconds: 15),
        task: () => gate.future,
      );

      // 等待在途请求真正开始执行。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.inFlightCount, 1);

      // 账号切换 reset：在途请求完成时应被丢弃，等待者失败而非永久挂起。
      coordinator.reset();
      expect(coordinator.inFlightCount, 0);

      gate.complete('old-result');
      await expectLater(pending, throwsA(isA<KuaishouCooldownError>()));

      // reset 后新请求正常工作，且不被旧请求结果污染。
      final after = await coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'room_detail:new',
        task: () async => 'new-result',
      );
      expect(after, 'new-result');
    });

    test('reset 前已合并的等待者也不拿到旧会话结果', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      final gate = Completer<String>();

      final first = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'room_detail:shared',
        task: () => gate.future,
      );
      // 等待在途开始后，第二个同 key 请求应合并到同一 Future。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final merged = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'room_detail:shared',
        task: () async => 'should-not-run',
      );

      // reset 后旧结果完成：发起者与合并等待者都应失败，不交付旧数据。
      coordinator.reset();
      gate.complete('old-data');
      // 两个 handler 须在错误回调发生前同时挂载，避免 unhandled error。
      final firstExpect =
          expectLater(first, throwsA(isA<KuaishouCooldownError>()));
      final mergedExpect =
          expectLater(merged, throwsA(isA<KuaishouCooldownError>()));
      await Future.wait([firstExpect, mergedExpect]);
    });
  });

  group('KuaishouRequestCoordinator 日志脱敏', () {
    test('未传 logLabel 时日志不打印原始 key（兜底脱敏）', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      // 捕获 CoreLog 输出。
      final captured = <String>[];
      final previous = CoreLog.onPrintLog;
      CoreLog.onPrintLog = (level, message) => captured.add(message);
      try {
        await coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'room_detail:12345',
          cacheTtl: const Duration(seconds: 15),
          task: () async => 'ok',
        );
        await coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'room_detail:12345',
          cacheTtl: const Duration(seconds: 15),
          task: () async => 'ok',
        );
      } finally {
        CoreLog.onPrintLog = previous;
      }
      expect(
        captured.join('\n').contains('room_detail:12345'),
        isFalse,
        reason: '协调器日志不得出现完整 key（含 roomId）',
      );
    });
  });
}
