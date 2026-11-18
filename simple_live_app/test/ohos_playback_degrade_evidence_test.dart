import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/ohos_playback_degrade_evidence.dart';

void main() {
  group('OhosPlaybackDegradeEvidence', () {
    final start = DateTime(2026);

    /// 走一段缓冲：从 [at] 开始、持续 [duration]，返回是否触发。
    ///
    /// 只喂开始与结束两次采样，与鸿蒙真实行为一致：那里只在播放器状态变化时
    /// 回调，一段缓冲拿不到中间过程的采样。
    bool buffer(
      OhosPlaybackDegradeEvidence evidence, {
      required Duration at,
      required Duration duration,
    }) {
      final startTriggered = evidence.update(
        buffering: true,
        now: start.add(at),
      );
      final endTriggered = evidence.update(
        buffering: false,
        now: start.add(at + duration),
      );
      return startTriggered || endTriggered;
    }

    test('两次很短的缓冲脉冲不触发切线路', () {
      final evidence = OhosPlaybackDegradeEvidence();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 10),
          duration: const Duration(milliseconds: 400),
        ),
        isFalse,
      );
      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 70),
          duration: const Duration(milliseconds: 500),
        ),
        isFalse,
      );
    });

    test('单次长缓冲达到连续阈值即触发', () {
      final evidence = OhosPlaybackDegradeEvidence();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 10),
          duration: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('窗口内累计缓冲达标即触发', () {
      final evidence = OhosPlaybackDegradeEvidence();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 10),
          duration: const Duration(seconds: 3),
        ),
        isFalse,
      );
      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 20),
          duration: const Duration(seconds: 3),
        ),
        isTrue,
      );
    });

    test('短脉冲次数够多也触发', () {
      final evidence = OhosPlaybackDegradeEvidence();
      final results = <bool>[];
      for (var i = 0; i < 4; i++) {
        results.add(
          buffer(
            evidence,
            at: Duration(seconds: 10 + i * 3),
            duration: const Duration(milliseconds: 200),
          ),
        );
      }

      expect(results.take(3), everyElement(isFalse));
      expect(results.last, isTrue);
    });

    test('超出窗口的旧缓冲不再累计', () {
      final evidence = OhosPlaybackDegradeEvidence();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 10),
          duration: const Duration(seconds: 3),
        ),
        isFalse,
      );
      // 距上一段缓冲结束已超过 30 秒窗口。
      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 60),
          duration: const Duration(seconds: 3),
        ),
        isFalse,
      );
    });

    test('长时间稳定播放后清空既有证据', () {
      final evidence = OhosPlaybackDegradeEvidence();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 10),
          duration: const Duration(seconds: 3),
        ),
        isFalse,
      );
      evidence.update(
        buffering: false,
        now: start.add(const Duration(seconds: 45)),
      );
      expect(
        evidence.accumulatedBuffering(start.add(const Duration(seconds: 45))),
        Duration.zero,
      );
    });

    test('预热期内的起播缓冲不留证据', () {
      final evidence = OhosPlaybackDegradeEvidence();
      evidence.beginWarmup(start);

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 1),
          duration: const Duration(seconds: 6),
        ),
        isFalse,
      );
      expect(
        evidence.bufferStarts(start.add(const Duration(seconds: 7))),
        0,
      );
    });

    test('reset 清空证据与预热窗口', () {
      final evidence = OhosPlaybackDegradeEvidence(
        requiredContinuousBuffering: const Duration(seconds: 1),
      );
      evidence.beginWarmup(start);
      evidence.reset();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 1),
          duration: const Duration(seconds: 1),
        ),
        isTrue,
      );
    });

    test('触发后证据清零，下一轮重新累积', () {
      final evidence = OhosPlaybackDegradeEvidence();

      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 10),
          duration: const Duration(seconds: 5),
        ),
        isTrue,
      );
      expect(
        evidence.bufferStarts(start.add(const Duration(seconds: 15))),
        0,
      );
      expect(
        buffer(
          evidence,
          at: const Duration(seconds: 16),
          duration: const Duration(seconds: 1),
        ),
        isFalse,
      );
    });
  });
}
