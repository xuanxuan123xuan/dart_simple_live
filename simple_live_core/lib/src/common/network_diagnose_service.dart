import 'dart:async';
import 'dart:io';

import 'live_stream_protocol.dart';

/// 单个目标主机的诊断结果。
///
/// 注意：这里的 `lost`/`lossRate` 是 **TCP 建连失败** 的统计，不是网络丢包率。
/// 本服务只做 `Socket.connect` 建连探测（见 [NetworkDiagnoseService.diagnoseHost]），
/// 没有 ICMP ping 或传输层丢包统计，因此所有"丢包"表述都应理解为
/// "TCP 连接失败"，文案与 UI 不得写成"丢包率"。
class NetworkDiagnosisResult {
  final String host;
  final int samples;

  /// 建连失败次数（TCP 连接失败，非丢包）。
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

  /// 建连失败率（0-100）。TCP 连接失败率，不是丢包率。
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

/// 当前直播间的网络诊断：用 TCP 连接测延迟与连通性，帮助用户判断
/// 卡顿是网络问题还是平台/线路问题（纯 Dart，无需平台插件）。
class NetworkDiagnoseService {
  NetworkDiagnoseService._();

  /// 旧版公共 DNS TCP 443 探测目标。
  ///
  /// 公共 DNS 不保证开放 TCP 443，不能作为网络质量或丢包依据。
  /// 新代码应只探测当前播放 URL 的真实端点。
  @Deprecated('Use diagnosePlaybackUrl for the current playback endpoint.')
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

  /// 按播放 URL 的真实 host/port 进行 TCP 建连探测。
  /// URL 无效或缺少 host 时返回 null，不回退到固定 443 以免误导。
  static Future<NetworkDiagnosisResult?> diagnosePlaybackUrl(
    String url, {
    int samples = 5,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final uri = Uri.tryParse(url);
    final host = uri?.host.trim() ?? '';
    if (uri == null || host.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    final port = uri.port > 0
        ? uri.port
        : scheme == 'rtmp'
            ? 1935
            : scheme == 'http'
                ? 80
                : 443;
    return diagnoseHost(
      host,
      port: port,
      samples: samples,
      timeout: timeout,
    );
  }

  /// 汇总当前播放端点的 TCP 建连结果。
  ///
  /// 这里只描述当前直播线路是否可连接及连接耗时，不把 TCP 建连失败
  /// 表述为数据包丢失，也不据此评价用户的整体网络质量。
  static String summarizePlaybackEndpoint(NetworkDiagnosisResult? result) {
    if (result == null) {
      return "当前没有可检测的直播线路。";
    }
    if (result.lost >= result.samples) {
      return "当前直播线路不可达，可尝试切换线路或清晰度。";
    }
    if (result.lost > 0) {
      return "当前直播线路可连接，但 ${result.samples} 次探测中有 "
          "${result.lost} 次连接失败，可稍后重试或切换线路。";
    }
    return "当前直播线路可连接，连接耗时约 "
        "${result.avgMs.toStringAsFixed(0)}ms。";
  }

  /// 从最低延迟协议档的一组播放线路 URL 中选出 TCP 延迟最低的线路索引。
  ///
  /// [urls] 为直播流地址；先根据协议延迟档筛选，再取各自 host 测延迟。
  /// 档内全部失败时返回该档第一条，避免较高延迟协议因 TCP 探测失败被选中。
  /// 测速有总时间预算（[totalBudget]），超时返回最低延迟协议档的默认线路。
  static Future<int> findFastestLine(
    List<String> urls, {
    int samples = 1,
    Duration timeout = const Duration(milliseconds: 800),
    Duration totalBudget = const Duration(milliseconds: 1800),
  }) async {
    if (urls.length <= 1) {
      return 0;
    }

    final candidateIndices = lowestLatencyLineIndices(urls);
    if (candidateIndices.length <= 1) {
      return candidateIndices.isEmpty ? 0 : candidateIndices.first;
    }

    final endpoints = <(String, int)>[];
    final indexByEndpoint = <(String, int), int>{};
    for (final i in candidateIndices) {
      final uri = Uri.tryParse(urls[i]);
      final host = uri?.host.toLowerCase() ?? "";
      if (host.isEmpty) continue;
      // URI provides defaults for HTTP(S). RTMP has no Dart URI default.
      final port = uri!.port > 0
          ? uri.port
          : uri.scheme.toLowerCase() == 'rtmp'
              ? 1935
              : 443;
      final endpoint = (host, port);
      if (!indexByEndpoint.containsKey(endpoint)) {
        indexByEndpoint[endpoint] = i;
        endpoints.add(endpoint);
      }
    }
    if (endpoints.length <= 1) {
      return candidateIndices.first;
    }
    List<NetworkDiagnosisResult> results;
    try {
      results = await Future.wait(
        endpoints.map(
          (endpoint) => diagnoseHost(
            endpoint.$1,
            samples: samples,
            timeout: timeout,
            port: endpoint.$2,
          ),
        ),
      ).timeout(totalBudget);
    } on TimeoutException {
      // 总测速超时：走最低延迟协议档的默认线路。
      return candidateIndices.first;
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
      return candidateIndices.first;
    }
    return indexByEndpoint[endpoints[bestIndex]] ?? candidateIndices.first;
  }

  /// 汇总判断：供无分层上下文的调用方使用（自动网络诊断等）。
  ///
  /// 内部委托 [summarizeLayered] 的分层逻辑；无分层上下文（[playbackEndpoint]
  /// 为 null）时全部结果视为外部对照参与判断。
  static String summarize(List<NetworkDiagnosisResult> results) {
    return summarizeLayered(
      results,
      playbackEndpoint: null,
      externalTargets: results,
    );
  }

  /// 分层诊断汇总：
  ///
  /// 1. 当前播放端点可连接，且外部对照部分失败 → 不判定本地断网，
  ///    归因到测速目标不可达或线路问题；
  /// 2. 播放端点失败但外部对照成功 → 优先判断平台/CDN/线路问题；
  /// 3. 播放端点与多个外部对照均失败 → 提示本地网络/代理/防火墙问题；
  /// 4. 少量连接失败 → 提示"探测结果不稳定"，不做精确百分比归因。
  ///
  /// [playbackEndpoint] 为当前播放 URL 的真实 (host, port) 探测结果，
  /// [externalTargets] 为外部对照目标结果。不做简单百分比平均。
  static String summarizeLayered(
    List<NetworkDiagnosisResult> results, {
    NetworkDiagnosisResult? playbackEndpoint,
    required List<NetworkDiagnosisResult> externalTargets,
  }) {
    if (results.isEmpty) return "无诊断数据";

    final externals = externalTargets.isNotEmpty ? externalTargets : results;
    final externalReachable = externals.where((r) => r.lost < r.samples).length;
    final externalTotal = externals.length;

    // 完全不可达的目标数（lost == samples）。
    final unreachableCount = results.where((r) => r.lost == r.samples).length;
    final totalLost = results.fold<int>(0, (sum, r) => sum + r.lost);
    final totalSamples = results.fold<int>(0, (sum, r) => sum + r.samples);

    // 3. 播放端点与外部对照均失败 → 本地网络/代理/防火墙。
    final allExternalLost = externalReachable == 0;
    final playback = playbackEndpoint;
    final playbackLost = playback != null && playback.lost == playback.samples;
    final playbackReachable =
        playback != null && playback.lost < playback.samples;

    if (playback != null && playbackLost && allExternalLost) {
      return "播放端点与外部目标均无法连接，可能是本地网络、代理或防火墙问题。";
    }

    // 2. 播放端点失败，但外部对照成功 → 平台/CDN/线路问题。
    if (playback != null && playbackLost) {
      return "当前直播线路连接失败，但外部网络正常，可能是平台或 CDN 线路问题，可尝试切换线路/清晰度。";
    }

    // 播放端点可达但外部对照全 lost：本地网络显然通（直播能连），
    // 归因到固定测速目标不可达（被屏蔽/运营商限制），而非本地断网。
    if (allExternalLost) {
      if (playbackReachable) {
        return "播放端点可连接，但外部测速目标不可达，可能是测速目标被屏蔽或运营商限制；直播可用则无需处理。";
      }
      if (playback == null) {
        return "外部测速目标均无法连接，当前没有播放端点数据，无法据此判断本地网络；请结合直播线路重试。";
      }
      return "所有外部测速目标均无法连接，多半是本地网络异常（断网/被拦截/需要代理）。";
    }

    // 4. 少量失败不归因：有目标完全不可达，或失败占比显著，才明确提示；
    //    否则各目标仍有可达样本，说明链路基本连通，不做"精确百分比"误判。
    if (unreachableCount > 0) {
      return "探测完成：$unreachableCount 个目标完全不可达"
          "（总失败 $totalLost/$totalSamples 次），"
          "$externalReachable/$externalTotal 个外部目标可达；"
          "若卡顿可尝试切换线路/清晰度。";
    }
    if (totalLost > 0 && totalSamples > 0) {
      final lossRatio = totalLost / totalSamples;
      if (lossRatio > 0.2) {
        return "探测结果不稳定（部分目标连接失败 $totalLost/$totalSamples 次），"
            "可尝试切换线路/代理。";
      }
      // 失败占比小（<=20%）且无目标完全不可达：视为偶发，继续按延迟判断。
    }

    // 平均延迟只统计"有成功样本"的目标。
    final reachable = results.where((r) => r.lost < r.samples).toList();
    final avgAvg = reachable.isEmpty
        ? 0.0
        : reachable.map((r) => r.avgMs).reduce((a, b) => a + b) /
            reachable.length;

    if (avgAvg > 250) {
      return "平均延迟较高（${avgAvg.toStringAsFixed(0)}ms），网络较慢，可尝试切换线路或代理。";
    }
    if (avgAvg < 120) {
      return "网络状态良好。若仍卡顿，多半是直播平台侧或当前线路问题，可尝试切换线路/清晰度。";
    }
    return "网络状态一般（延迟 ${avgAvg.toStringAsFixed(0)}ms），若卡顿可切换线路试试。";
  }
}
