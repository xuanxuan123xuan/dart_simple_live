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

  group('KuaishouRequestCoordinator 逻辑操作合并', () {
    test('外层详情合并不占用物理队列，内部可串行多个 HTTP 任务', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      var logicalCalls = 0;
      var physicalCalls = 0;

      Future<String> detailTask() => coordinator.coalesce(
            key: 'detail:1',
            cacheTtl: const Duration(seconds: 10),
            task: () async {
              logicalCalls++;
              await coordinator.schedule(
                priority: KuaishouRequestPriority.userEnter,
                key: 'http:handshake:1',
                task: () async => physicalCalls++,
              );
              await coordinator.schedule(
                priority: KuaishouRequestPriority.userEnter,
                key: 'http:page:1',
                task: () async => physicalCalls++,
              );
              return 'detail';
            },
          );

      expect(await Future.wait([detailTask(), detailTask()]),
          ['detail', 'detail']);
      expect(logicalCalls, 1);
      expect(physicalCalls, 2);
      expect(await detailTask(), 'detail');
      expect(logicalCalls, 1);
    });

    test('可按结果设置不同 TTL', () async {
      var now = DateTime(2026, 1, 1);
      final coordinator = KuaishouRequestCoordinator(
        nowProvider: () => now,
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      var calls = 0;
      Future<String> load() => coordinator.coalesce(
            key: 'status:1',
            cacheTtlForValue: (value) => value == 'offline'
                ? const Duration(minutes: 3)
                : const Duration(seconds: 30),
            task: () async {
              calls++;
              return 'offline';
            },
          );

      await load();
      now = now.add(const Duration(minutes: 2));
      await load();
      expect(calls, 1);
      now = now.add(const Duration(minutes: 2));
      await load();
      expect(calls, 2);
    });

    test('forceNetwork 绕过已完成缓存但仍合并同时请求', () async {
      final coordinator = KuaishouRequestCoordinator();
      var calls = 0;
      Future<int> load({bool forceNetwork = false}) => coordinator.coalesce(
            key: 'status:force',
            cacheTtl: const Duration(minutes: 1),
            bypassCache: forceNetwork,
            task: () async => ++calls,
          );

      expect(await load(), 1);
      expect(await load(), 1);
      expect(
          await Future.wait(
              [load(forceNetwork: true), load(forceNetwork: true)]),
          [2, 2]);
      expect(calls, 2);
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
    test('用户主动进房只插队，仍遵守物理请求最小间隔', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: const Duration(milliseconds: 200),
        maxJitter: Duration.zero,
      );
      final order = <String>[];
      final starts = <int>[];

      // 先入队两个后台请求（会因最小间隔被节流）。
      final follow = coordinator.schedule(
        priority: KuaishouRequestPriority.followRefresh,
        key: 'follow',
        task: () async {
          order.add('follow');
          starts.add(DateTime.now().millisecondsSinceEpoch);
          return 'follow';
        },
      );
      final status = coordinator.schedule(
        priority: KuaishouRequestPriority.roomStatus,
        key: 'status',
        task: () async {
          order.add('status');
          starts.add(DateTime.now().millisecondsSinceEpoch);
          return 'status';
        },
      );
      // 用户主动进房应插到已排队的后台任务前，但不跳过出站间隔。
      final enter = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'enter',
        task: () async {
          order.add('enter');
          starts.add(DateTime.now().millisecondsSinceEpoch);
          return 'enter';
        },
      );

      final results = await Future.wait([follow, status, enter]);
      expect(results, ['follow', 'status', 'enter']);
      expect(order.contains('enter'), isTrue);
      expect(order.first, 'follow');
      expect(order, ['follow', 'enter', 'status']);
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(200));
      }
    });
  });

  group('KuaishouRequestCoordinator 冷却', () {
    test('冷却期停发；到期后只允许一次探针（用户进房优先）', () async {
      var now = DateTime(2026, 1, 1);
      final coordinator = KuaishouRequestCoordinator(
        nowProvider: () => now,
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      coordinator.beginCooldown(const Duration(minutes: 5));

      // 后台请求应直接失败。
      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'background',
          task: () async => 'ok',
        ),
        throwsA(isA<KuaishouCooldownError>()),
      );

      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'enter-during-cooldown',
          task: () async => 'blocked',
        ),
        throwsA(isA<KuaishouCooldownError>()),
      );

      now = now.add(const Duration(minutes: 6));
      // 冷却到期后第一个探针名额被用户进房领走，其余后台请求仍被拒。
      expect(
        await coordinator.schedule(
          priority: KuaishouRequestPriority.userEnter,
          key: 'probe',
          task: () async => 'probe-ok',
        ),
        'probe-ok',
      );
      final after = await coordinator.schedule(
        priority: KuaishouRequestPriority.followRefresh,
        key: 'after',
        task: () async => 'ok',
      );
      expect(after, 'ok');
    });

    test('冷却到期后关注刷新也能当探针，无需用户先进房', () async {
      var now = DateTime(2026, 1, 1);
      final coordinator = KuaishouRequestCoordinator(
        nowProvider: () => now,
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      coordinator.beginCooldown(const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 6));

      // 只看关注页、不点进直播间时，后台刷新自己就能把冷却探测掉。
      expect(
        await coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'follow-probe',
          task: () async => 'probe-ok',
        ),
        'probe-ok',
      );
      expect(coordinator.inCooldown, isFalse);

      // 探针成功后恢复常规后台流量。
      expect(
        await coordinator.schedule(
          priority: KuaishouRequestPriority.roomStatus,
          key: 'after-follow-probe',
          task: () async => 'ok',
        ),
        'ok',
      );
    });

    test('探针失败后归还名额，下一次请求仍可重新探测', () async {
      var now = DateTime(2026, 1, 1);
      final coordinator = KuaishouRequestCoordinator(
        nowProvider: () => now,
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      coordinator.beginCooldown(const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 6));

      await expectLater(
        coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'failing-probe',
          task: () async => throw StateError('probe failed'),
        ),
        throwsA(isA<StateError>()),
      );

      // 名额未归还时，这里会永久停在「等待恢复探针」，冷却再也退不出去。
      expect(
        await coordinator.schedule(
          priority: KuaishouRequestPriority.followRefresh,
          key: 'retry-probe',
          task: () async => 'probe-ok',
        ),
        'probe-ok',
      );
      expect(coordinator.inCooldown, isFalse);
    });

    test('cancelScope 只取消同作用域中尚未执行的请求', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      );
      final gate = Completer<void>();
      final running = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'running',
        task: () async {
          await gate.future;
          return 'running';
        },
      );
      final canceled = coordinator.schedule(
        priority: KuaishouRequestPriority.followRefresh,
        key: 'queued-canceled',
        scopeId: 'follow',
        task: () async => 'wrong',
      );
      final kept = coordinator.schedule(
        priority: KuaishouRequestPriority.catalogBackground,
        key: 'queued-kept',
        scopeId: 'catalog',
        task: () async => 'kept',
      );

      coordinator.cancelScope('follow');
      await expectLater(
        canceled,
        throwsA(isA<KuaishouRequestCanceledError>()),
      );
      gate.complete();
      expect(await running, 'running');
      expect(await kept, 'kept');
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

    test('reset 后新账号会等待旧物理请求完成并保留全局间隔', () async {
      final coordinator = KuaishouRequestCoordinator(
        minInterval: const Duration(milliseconds: 100),
        maxJitter: Duration.zero,
      );
      final gate = Completer<void>();
      final starts = <int>[];
      var active = 0;
      var maxActive = 0;

      final oldRequest = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'old-account',
        task: () async {
          starts.add(DateTime.now().millisecondsSinceEpoch);
          active++;
          maxActive = active;
          await gate.future;
          active--;
          return 'old';
        },
      );
      final oldExpectation =
          expectLater(oldRequest, throwsA(isA<KuaishouCooldownError>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.reset();
      final newRequest = coordinator.schedule(
        priority: KuaishouRequestPriority.userEnter,
        key: 'new-account',
        task: () async {
          starts.add(DateTime.now().millisecondsSinceEpoch);
          active++;
          if (active > maxActive) maxActive = active;
          active--;
          return 'new';
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(starts, hasLength(1), reason: '旧账号在途时不得启动新账号请求');
      gate.complete();
      await oldExpectation;
      expect(await newRequest, 'new');
      expect(maxActive, 1);
      expect(starts[1] - starts[0], greaterThanOrEqualTo(100));
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
