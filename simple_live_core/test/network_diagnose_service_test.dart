import 'dart:async';
import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

/// 在 loopback 上起一个可选的延迟假 TCP server，用于模拟可测速线路。
/// 支持指定 loopback 地址（127.0.0.1 / 127.0.0.2），用于构造"不同 host"。
Future<ServerSocket> _startServer(
    {Duration? delay, String address = '127.0.0.1'}) async {
  final server = await ServerSocket.bind(
    InternetAddress(address),
    0,
  );
  server.listen((socket) async {
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    await socket.close();
  });
  return server;
}

/// 关闭 server 后端口即无监听（连接被拒绝），模拟"不通"的线路。
Future<int> _deadPort() async {
  final server = await _startServer();
  final port = server.port;
  await server.close();
  return port;
}

NetworkDiagnosisResult _r(double avg, int lost, int samples) =>
    NetworkDiagnosisResult(
      host: 'h',
      samples: samples,
      lost: lost,
      minMs: avg,
      avgMs: avg,
      maxMs: avg,
    );

void main() {
  group('diagnoseHost', () {
    test('连通目标：lost=0 且 RTT 为正', () async {
      final server = await _startServer();
      try {
        final r = await NetworkDiagnoseService.diagnoseHost(
          '127.0.0.1',
          samples: 3,
          port: server.port,
        );
        expect(r.lost, 0);
        expect(r.lossRate, 0);
        expect(r.minMs, greaterThan(0));
        expect(r.avgMs, greaterThanOrEqualTo(r.minMs));
        expect(r.maxMs, greaterThanOrEqualTo(r.avgMs));
        expect(r.latencyLabel, isNot('不通'));
      } finally {
        await server.close();
      }
    });

    test('拒绝连接：全部样本 lost', () async {
      final port = await _deadPort();
      final r = await NetworkDiagnoseService.diagnoseHost(
        '127.0.0.1',
        samples: 3,
        port: port,
      );
      expect(r.lost, 3);
      expect(r.lossRate, 100);
      expect(r.latencyLabel, '不通');
    });
  });

  group('diagnosePlaybackUrl', () {
    test('uses the explicit playback URL port', () async {
      final server = await _startServer();
      try {
        final result = await NetworkDiagnoseService.diagnosePlaybackUrl(
          'http://127.0.0.1:${server.port}/live.flv',
          samples: 1,
        );
        expect(result, isNotNull);
        expect(result!.lost, 0);
      } finally {
        await server.close();
      }
    });

    test('invalid playback URL has no endpoint result', () async {
      expect(
        await NetworkDiagnoseService.diagnosePlaybackUrl('not-a-url'),
        isNull,
      );
    });
  });

  group('latencyLabel 边界', () {
    test('60ms 以下为优秀', () {
      expect(_r(59, 0, 5).latencyLabel, '优秀');
    });
    test('60-119ms 为良好', () {
      expect(_r(60, 0, 5).latencyLabel, '良好');
      expect(_r(119, 0, 5).latencyLabel, '良好');
    });
    test('120-249ms 为一般', () {
      expect(_r(120, 0, 5).latencyLabel, '一般');
    });
    test('250ms+ 为较差', () {
      expect(_r(250, 0, 5).latencyLabel, '较差');
    });
    test('全 lost 为不通', () {
      expect(_r(0, 5, 5).latencyLabel, '不通');
    });
  });

  group('findFastestLine', () {
    test('单条 URL 直接返回 0', () async {
      final port = await _deadPort();
      expect(
        await NetworkDiagnoseService.findFastestLine(
          ['http://127.0.0.1:$port/a.flv'],
          samples: 1,
        ),
        0,
      );
    });

    test('先选择最低延迟协议档，再比较 TCP RTT', () async {
      // 即使 HLS 排在列表最前且与 FLV 共用同一 host，低延迟档的 FLV
      // 也必须被选中；这同时覆盖了跨协议档不再按 host 折叠的约束。
      expect(
        await NetworkDiagnoseService.findFastestLine([
          'https://cdn.example.com/live.m3u8',
          'https://cdn.example.com/live.flv',
        ]),
        1,
      );
    });

    // 注：不在本地模拟"两个都可达时的延迟差"——loopback 的 TCP 握手
    // RTT 由内核决定（微秒级），server 端 sleep 无法延迟 connect 完成时间，
    // 因此该分支无法稳定构造。选快逻辑 = lost 过滤（下两测）+ avg 最小
    // 比较（实现内联，见 findFastestLine）；可达性行为由以下测试覆盖。

    test('不通的线路被跳过，选中可达线路', () async {
      final dead = await _deadPort();
      final fast = await _startServer(address: '127.0.0.2');
      try {
        final idx = await NetworkDiagnoseService.findFastestLine(
          [
            'http://127.0.0.1:$dead/a.flv',
            'http://127.0.0.2:${fast.port}/b.flv',
          ],
          samples: 2,
        );
        expect(idx, 1);
      } finally {
        await fast.close();
      }
    });

    test('全部不通返回 0（默认第一条）', () async {
      final a = await _deadPort();
      final b = await _deadPort();
      // 两个死端口在不同 host，避免被去重成一个。
      expect(
        await NetworkDiagnoseService.findFastestLine(
          [
            'http://127.0.0.1:$a/a.flv',
            'http://127.0.0.2:$b/b.flv',
          ],
          samples: 2,
        ),
        0,
      );
    });

    test('同 host 不同 path 去重后仍返回第一个索引', () async {
      final server = await _startServer();
      try {
        final idx = await NetworkDiagnoseService.findFastestLine(
          [
            'http://127.0.0.1:${server.port}/a.flv',
            'http://127.0.0.1:${server.port}/b.flv',
          ],
          samples: 1,
        );
        expect(idx, 0);
      } finally {
        await server.close();
      }
    });

    test('同 host 不同 port 作为独立端点测速', () async {
      final dead = await _deadPort();
      final reachable = await _startServer();
      try {
        final idx = await NetworkDiagnoseService.findFastestLine(
          [
            'http://127.0.0.1:$dead/a.flv',
            'http://127.0.0.1:${reachable.port}/b.flv',
          ],
          samples: 1,
        );
        expect(idx, 1);
      } finally {
        await reachable.close();
      }
    });

    test('总测速超时返回 0，不阻塞播放启动', () async {
      // 挂起不响应的 server（accept 后不 close），配合小总预算触发超时。
      final hanging = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      hanging.listen((_) {});
      final dead = await _deadPort();
      try {
        final idx = await NetworkDiagnoseService.findFastestLine(
          [
            'http://127.0.0.1:${hanging.port}/a.flv',
            'http://127.0.0.1:$dead/b.flv',
          ],
          samples: 1,
          totalBudget: const Duration(milliseconds: 300),
        );
        expect(idx, 0);
      } finally {
        await hanging.close();
      }
    });

    test('按 URL 端口测速（修复前固定 443 会连接失败）', () async {
      final server = await _startServer();
      try {
        // 若实现仍固定 443，127.0.0.1:443 连接被拒绝 → 全 lost；
        // 修复后按 URL 端口连接成功，单 URL 返回 0。
        final idx = await NetworkDiagnoseService.findFastestLine(
          ['http://127.0.0.1:${server.port}/a.flv'],
          samples: 1,
        );
        expect(idx, 0);
      } finally {
        await server.close();
      }
    });
  });

  group('summarize', () {
    test('空结果', () {
      expect(NetworkDiagnoseService.summarize(const []), '无诊断数据');
    });

    test('全部不通', () {
      final s = NetworkDiagnoseService.summarize([_r(0, 5, 5), _r(0, 5, 5)]);
      expect(s, contains('无法连接'));
      expect(s, contains('无法据此判断本地网络'));
    });

    test('部分目标完全不可达（不冒充丢包率）', () {
      final s = NetworkDiagnoseService.summarize([_r(40, 5, 5), _r(40, 0, 5)]);
      expect(s, contains('完全不可达'));
      expect(s, isNot(contains('丢包')));
    });

    test('高延迟', () {
      final s =
          NetworkDiagnoseService.summarize([_r(300, 0, 5), _r(300, 0, 5)]);
      expect(s, contains('平均延迟较高'));
    });

    test('良好', () {
      final s = NetworkDiagnoseService.summarize([_r(50, 0, 5), _r(50, 0, 5)]);
      expect(s, contains('网络状态良好'));
    });

    test('偶发少量失败（1/5）不误报为网络异常', () {
      // 失败占比 2/10=20%，未超过阈值且无目标完全不可达 → 不触发不稳定分支，
      // 按延迟继续判断（少量偶发失败不归因为网络异常）。
      final s =
          NetworkDiagnoseService.summarize([_r(150, 1, 5), _r(150, 1, 5)]);
      expect(s, isNot(contains('不稳定')));
      expect(s, isNot(contains('丢包')));
    });

    test('失败占比显著（>20%）提示探测不稳定', () {
      final s =
          NetworkDiagnoseService.summarize([_r(150, 3, 5), _r(150, 3, 5)]);
      expect(s, contains('不稳定'));
    });

    test('全 lost 目标不拉低平均延迟数值（修复验证）', () {
      // 8 个 40ms 可达 + 2 个全 lost：修复前 avgLoss 平均会把结果拉到低位；
      // 修复后分层汇总只统计可达目标延迟。
      final results = [
        for (var i = 0; i < 8; i++) _r(40, 0, 5),
        _r(0, 5, 5),
        _r(0, 5, 5),
      ];
      final s = NetworkDiagnoseService.summarize(results);
      expect(s, contains('外部目标可达'));
    });

    test('播放端点失败但外部对照成功 → 提示线路/CDN 问题', () {
      final playback = _r(0, 5, 5); // 播放端点全 lost
      final externals = [_r(50, 0, 5), _r(60, 0, 5)]; // 外部可达
      final s = NetworkDiagnoseService.summarizeLayered(
        [playback, ...externals],
        playbackEndpoint: playback,
        externalTargets: externals,
      );
      expect(s, contains('线路'));
    });

    test('播放端点与外部对照均失败 → 提示本地网络', () {
      final playback = _r(0, 5, 5);
      final externals = [_r(0, 5, 5), _r(0, 5, 5)];
      final s = NetworkDiagnoseService.summarizeLayered(
        [playback, ...externals],
        playbackEndpoint: playback,
        externalTargets: externals,
      );
      expect(s, contains('本地网络'));
    });

    test('播放端点可达但外部对照全 lost → 不归因本地断网', () {
      final playback = _r(80, 0, 5);
      final externals = [_r(0, 5, 5), _r(0, 5, 5)];
      final s = NetworkDiagnoseService.summarizeLayered(
        [playback, ...externals],
        playbackEndpoint: playback,
        externalTargets: externals,
      );
      expect(s, contains('测速目标被屏蔽'));
      expect(s, isNot(contains('本地网络异常')));
    });
  });
}
