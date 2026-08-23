import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/live_link_health_presentation.dart';
import 'package:simple_live_core/simple_live_core.dart';

typedef QuickAccessItemCallback = FutureOr<void> Function(String key);

class LiveRoomQuickAccessPanel extends StatefulWidget {
  const LiveRoomQuickAccessPanel({
    super.key,
    required this.controller,
    required this.onOpenItem,
    required this.onClose,
    this.initialDiagnostics = false,
    this.isBottomSheet = false,
  });

  final LiveRoomController controller;
  final QuickAccessItemCallback onOpenItem;
  final VoidCallback onClose;
  final bool initialDiagnostics;
  final bool isBottomSheet;

  @override
  State<LiveRoomQuickAccessPanel> createState() =>
      _LiveRoomQuickAccessPanelState();
}

class _LiveRoomQuickAccessPanelState extends State<LiveRoomQuickAccessPanel> {
  bool _showDiagnostics = false;
  bool _diagnosticsRunning = false;
  NetworkDiagnosisResult? _endpointResult;
  LiveLinkHealthPresentation? _healthPresentation;
  List<MapEntry<String, String>> _playbackRows = const [];
  String _summary = "";

  @override
  void initState() {
    super.initState();
    _showDiagnostics = widget.initialDiagnostics;
    if (_showDiagnostics) {
      unawaited(_runDiagnostics());
    }
  }

  /// 诊断页是否由快捷入口列表进入。直接以诊断页作为入口时（设置里的
  /// “网络诊断与播放信息”），用户从未经过快捷入口，所以不提供返回快捷入口的路径。
  bool get _canReturnToQuickAccess =>
      _showDiagnostics && !widget.initialDiagnostics;

  @override
  Widget build(BuildContext context) {
    // 这里不拦截 pop：点击遮罩走的是 Navigator.maybePop，与系统返回同一条路径，
    // 一旦拦截就会被吞成“退回快捷入口”而关不掉容器。返回快捷入口只保留头部箭头
    // 这一个显式入口，pop 一律直接关闭整个面板。
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _showDiagnostics
          ? _buildDiagnosticsPage()
          : _buildQuickAccessPage(),
    );
  }

  Widget _buildQuickAccessPage() {
    final keys = widget.controller.enabledQuickAccessKeys;
    if (keys.isEmpty) {
      return ListView(
        key: const ValueKey("quick_access_empty"),
        children: [
          _buildPanelHeader(),
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text("没有已启用的快捷入口")),
          ),
        ],
      );
    }
    return ListView(
      key: const ValueKey("quick_access_list"),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _buildPanelHeader(),
        ...keys.map(_buildQuickAccessTile),
      ],
    );
  }

  Widget _buildQuickAccessTile(String key) {
    final item = Constant.allLiveRoomQuickAccess[key]!;
    final enabled =
        key != "recommendation" || widget.controller.hasCategoryRecommendation;
    return ListTile(
      leading: Icon(item.iconData),
      title: Text(widget.controller.quickAccessTitle(key)),
      subtitle: Text(widget.controller.quickAccessSubtitle(key)),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: !enabled
          ? null
          : () {
              if (key == "network_diagnostics") {
                setState(() => _showDiagnostics = true);
                unawaited(_runDiagnostics());
                return;
              }
              widget.onOpenItem(key);
            },
    );
  }

  Widget _buildDiagnosticsPage() {
    return ListView(
      key: const ValueKey("quick_access_diagnostics"),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        _buildPanelHeader(),
        if (_diagnosticsRunning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          _buildHealthSection(),
          const SizedBox(height: 12),
          _buildSectionTitle("网络诊断"),
          _buildEndpointSection(),
          const SizedBox(height: 12),
          _buildSectionTitle("播放信息"),
          _buildPlaybackSection(),
        ],
      ],
    );
  }

  Widget _buildPanelHeader() {
    final diagnostics = _showDiagnostics;
    final canReturn = _canReturnToQuickAccess;
    return Row(
      children: [
        IconButton(
          tooltip: canReturn ? "返回快捷入口" : "关闭",
          onPressed: canReturn
              ? () => setState(() => _showDiagnostics = false)
              : widget.onClose,
          icon: Icon(
            canReturn
                ? Icons.arrow_back
                : (diagnostics || widget.isBottomSheet
                    ? Icons.close
                    : Icons.arrow_back),
          ),
        ),
        Expanded(
          child: Text(
            diagnostics ? "网络诊断与播放信息" : "快捷入口",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (diagnostics)
          IconButton(
            tooltip: "重新测试",
            onPressed: _diagnosticsRunning ? null : _runDiagnostics,
            icon: const Icon(Icons.refresh),
          ),
        if (canReturn && widget.isBottomSheet)
          IconButton(
            tooltip: "关闭",
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildHealthSection() {
    final presentation = _healthPresentation;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "直播链路健康度",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                presentation?.levelLabel ?? liveLinkHealthDataUnavailableLabel,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Text(
                presentation?.scoreLabel ?? liveLinkHealthDataUnavailableLabel,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "主要原因：${presentation?.primaryCauseLabel ?? liveLinkHealthDataUnavailableLabel}",
            style: const TextStyle(fontSize: 12),
          ),
          if (presentation != null) ...[
            const SizedBox(height: 8),
            for (final row in presentation.rows)
              _buildValueRow(row.label, row.value),
          ],
        ],
      ),
    );
  }

  Widget _buildEndpointSection() {
    final result = _endpointResult;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result != null) ...[
            _buildValueRow("当前播放端点", result.host),
            _buildValueRow(
              "连接状态",
              result.lost == result.samples
                  ? "不可达"
                  : result.lost > 0
                      ? "${result.samples} 次中 ${result.lost} 次连接失败"
                      : "连接正常",
            ),
            _buildValueRow(
              "连接耗时",
              result.lost == result.samples
                  ? "不可达"
                  : "${result.avgMs.toStringAsFixed(0)}ms（${result.latencyLabel}）",
            ),
          ],
          Text(
            _summary.isEmpty ? "当前没有可检测的直播线路。" : _summary,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSection() {
    if (_playbackRows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text("当前没有可显示的播放信息"),
      );
    }
    final primaryRows = _playbackRows.take(6).toList();
    final detailRows = _playbackRows.skip(6).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (final row in primaryRows)
                  _buildCopyableValueRow(row.key, row.value),
              ],
            ),
          ),
          if (detailRows.isNotEmpty)
            ExpansionTile(
              title: const Text("详细播放信息"),
              children: [
                for (final row in detailRows)
                  ListTile(
                    dense: true,
                    title: Text(row.key),
                    subtitle: Text(row.value),
                    onTap: () => _copyValue(row.key, row.value),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableValueRow(String label, String value) {
    return InkWell(
      onTap: () => _copyValue(label, value),
      child: _buildValueRow(label, value),
    );
  }

  Future<void> _copyValue(String label, String value) {
    return Clipboard.setData(ClipboardData(text: "$label\n$value"));
  }

  Future<void> _runDiagnostics() async {
    if (_diagnosticsRunning) return;
    setState(() => _diagnosticsRunning = true);

    NetworkDiagnosisResult? endpointResult;
    List<MapEntry<String, String>> playbackRows = const [];
    String summary = "";
    final endpointFuture = NetworkDiagnoseService.diagnosePlaybackUrl(
      widget.controller.currentNetworkDiagnosePlaybackUrl,
    );
    final playbackRowsFuture = widget.controller.readPlaybackDiagnosticRows();
    try {
      endpointResult = await endpointFuture;
      summary = NetworkDiagnoseService.summarizePlaybackEndpoint(
        endpointResult,
      );
    } catch (_) {
      summary = "诊断暂时失败，请稍后重试。";
    }
    try {
      playbackRows = await playbackRowsFuture;
    } catch (_) {
      playbackRows = const [];
    }
    if (!mounted) return;

    final healthSnapshot = widget.controller.currentLiveLinkHealthSnapshot;
    setState(() {
      _endpointResult = endpointResult;
      _playbackRows = playbackRows;
      _healthPresentation = healthSnapshot == null
          ? null
          : presentLiveLinkHealthSnapshot(
              healthSnapshot,
              currentBuffering:
                  widget.controller.currentLiveLinkHealthBuffering,
            );
      _summary = summary;
      _diagnosticsRunning = false;
    });
  }
}
