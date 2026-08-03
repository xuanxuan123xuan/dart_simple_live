import 'dart:async';
import 'dart:io';

/// 单个目标主机的诊断结果。
class NetworkDiagnosisResult {
  final String host;
  final int samples;
  final int lost;
  final double minMs;
  final double avgMs;
  final double maxMs;

  const NetworkDiagnosisResult({
    required this.host,
    required this.samples,
    required this.lost,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
  });

  /// 丢包率（0-100）。
  double get lossRate => samples == 0 ? 0 : lost / samples * 100;

  /// 延迟评级。
  String get latencyLabel {
    if (lost == samples) return "不通";
    if (avgMs < 60) return "优秀";
    if (avgMs < 120) return "良好";
    if (avgMs < 250) return "一般";
    return "较差";
  }
}

/// 当前直播间的网络诊断：用 TCP 连接测延迟与丢包，帮助用户判断
/// 卡顿是网络问题还是平台/线路问题（纯 Dart，无需平台插件）。
class NetworkDiagnoseService {
  NetworkDiagnoseService._();

  /// 常用测速目标（公共 DNS，稳定可达）。
  static const List<String> defaultTargets = [
    "223.5.5.5", // 阿里 DNS
    "114.114.114.114", // 114 DNS
    "8.8.8.8", // Google DNS
  ];

  static Future<NetworkDiagnosisResult> diagnoseHost(
    String host, {
    int samples = 5,
    int port = 443,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final rtts = <double>[];
    var lost = 0;
    for (var i = 0; i < samples; i += 1) {
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        await socket.close();
        stopwatch.stop();
        rtts.add(stopwatch.elapsedMicroseconds / 1000.0);
      } catch (_) {
        lost += 1;
      }
      if (i < samples - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    final ok = rtts.isNotEmpty ? rtts : [0.0];
    return NetworkDiagnosisResult(
      host: host,
      samples: samples,
      lost: lost,
      minMs: ok.reduce((a, b) => a < b ? a : b),
      avgMs: ok.reduce((a, b) => a + b) / ok.length,
      maxMs: ok.reduce((a, b) => a > b ? a : b),
    );
  }

  /// 对一组目标并发诊断，返回按平均延迟排序的结果。
  static Future<List<NetworkDiagnosisResult>> diagnose(
    List<String> targets, {
    int samples = 5,
  }) async {
    return Future.wait(
      targets.map((host) => diagnoseHost(host, samples: samples)),
    );
  }

  /// 从一组播放线路 URL 中选出 TCP 延迟最低的线路索引。
  ///
  /// [urls] 为直播流地址；取各自 host 测延迟。全部失败返回 0。
  /// 测速有总时间预算（[totalBudget]），超时直接返回 0（默认第一条线路），
  /// 不会阻塞播放启动太久。
  static Future<int> findFastestLine(
    List<String> urls, {
    int samples = 1,
    Duration timeout = const Duration(milliseconds: 800),
    Duration totalBudget = const Duration(milliseconds: 1800),
  }) async {
    if (urls.length <= 1) {
      return 0;
    }
    final hosts = <String>[];
    final indexByHost = <String, int>{};
    final portByHost = <String, int>{};
    for (var i = 0; i < urls.length; i += 1) {
      final uri = Uri.tryParse(urls[i]);
      final host = uri?.host ?? "";
      if (host.isEmpty) continue;
      if (!indexByHost.containsKey(host)) {
        indexByHost[host] = i;
        hosts.add(host);
        // 按线路实际 scheme/port 测速（http=80 / https=443 / 显式端口）；
        // 无法解析（如 rtmp）时回退 443，与旧行为一致。
        portByHost[host] = uri!.port > 0 ? uri.port : 443;
      }
    }
    if (hosts.length <= 1) {
      return 0;
    }
    List<NetworkDiagnosisResult> results;
    try {
      results = await Future.wait(
        hosts.map(
          (host) => diagnoseHost(
            host,
            samples: samples,
            timeout: timeout,
            port: portByHost[host]!,
          ),
        ),
      ).timeout(totalBudget);
    } on TimeoutException {
      // 总测速超时：不阻塞播放，走默认第一条线路。
      return 0;
    }
    var bestIndex = 0;
    var bestLatency = double.infinity;
    for (var i = 0; i < results.length; i += 1) {
      final r = results[i];
      if (r.lost == r.samples) {
        continue; // 完全不通，跳过
      }
      if (r.avgMs < bestLatency) {
        bestLatency = r.avgMs;
        bestIndex = i;
      }
    }
    if (bestLatency == double.infinity) {
      return 0;
    }
    return indexByHost[hosts[bestIndex]] ?? 0;
  }

  /// 汇总判断：网络是否健康。
  static String summarize(List<NetworkDiagnosisResult> results) {
    if (results.isEmpty) return "无诊断数据";
    final allLost = results.every((r) => r.lost == r.samples);
    if (allLost) {
      return "所有测速目标均无法连接，多半是本地网络异常（断网/被拦截/需要代理）。";
    }
    // 平均延迟只统计"有成功样本"的目标；全 lost 目标 avgMs=0，
    // 直接参与均值会把结果拉到不真实的低位。
    final reachable = results.where((r) => r.lost < r.samples).toList();
    final avgAvg = reachable.isEmpty
        ? 0.0
        : reachable.map((r) => r.avgMs).reduce((a, b) => a + b) /
            reachable.length;
    final avgLoss = results.map((r) => r.lossRate).reduce((a, b) => a + b) /
        results.length;
    if (avgLoss > 20) {
      return "丢包率偏高（${avgLoss.toStringAsFixed(0)}%），网络不稳定，建议检查 WiFi/代理。";
    }
    if (avgAvg > 250) {
      return "平均延迟较高（${avgAvg.toStringAsFixed(0)}ms），网络较慢，可尝试切换线路或代理。";
    }
    if (avgAvg < 120 && avgLoss < 5) {
      return "网络状态良好。若仍卡顿，多半是直播平台侧或当前线路问题，可尝试切换线路/清晰度。";
    }
    return "网络状态一般（延迟 ${avgAvg.toStringAsFixed(0)}ms / 丢包 ${avgLoss.toStringAsFixed(0)}%），若卡顿可切换线路试试。";
  }
}
