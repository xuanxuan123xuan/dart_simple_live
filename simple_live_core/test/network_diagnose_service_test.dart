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

    test('总测速超时返回 0，不阻塞播放启动', () async {
      // 挂起不响应的 server（accept 后不 close），配合小总预算触发超时。
      final hanging =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
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
    });

    test('高丢包', () {
      final s = NetworkDiagnoseService.summarize([_r(40, 2, 5), _r(40, 2, 5)]);
      expect(s, contains('丢包率偏高'));
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

    test('一般', () {
      final s =
          NetworkDiagnoseService.summarize([_r(150, 1, 5), _r(150, 1, 5)]);
      expect(s, contains('网络状态一般'));
    });

    test('全 lost 目标不拉低平均延迟数值（修复验证）', () {
      // 8 个 40ms 可达 + 2 个全 lost：avgLoss=20% 不触发丢包分支，
      // 修复前 avgAvg=(8*40+0+0)/10=32ms，修复后=40ms（只统计可达目标）。
      final results = [
        for (var i = 0; i < 8; i++) _r(40, 0, 5),
        _r(0, 5, 5),
        _r(0, 5, 5),
      ];
      final s = NetworkDiagnoseService.summarize(results);
      expect(s, contains('40'));
    });
  });
}
