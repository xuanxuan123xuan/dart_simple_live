import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/signalr_service.dart';

class SyncServerPickerDialog extends StatefulWidget {
  const SyncServerPickerDialog({super.key});

  @override
  State<SyncServerPickerDialog> createState() => _SyncServerPickerDialogState();
}

class _SyncServerPickerDialogState extends State<SyncServerPickerDialog> {
  final Map<String, SyncServerProbeResult?> _results = {};

  @override
  void initState() {
    super.initState();
    for (final preset in SignalRService.kServerPresets) {
      _probe(preset.wsUrl);
    }
  }

  Future<void> _probe(String wsUrl) async {
    setState(() => _results[wsUrl] = null);
    final result = await SignalRService.probeServer(wsUrl);
    if (!mounted) return;
    setState(() => _results[wsUrl] = result);
  }

  String _statusText(String wsUrl) {
    if (!_results.containsKey(wsUrl)) return "";
    final result = _results[wsUrl];
    if (result == null) return "测试中…";
    if (result.ok) {
      return "可用 ${result.latencyMs}ms（${result.detail}）";
    }
    return "不可用：${result.detail}";
  }

  Color _statusColor(String wsUrl) {
    if (!_results.containsKey(wsUrl)) {
      return Colors.grey;
    }
    final result = _results[wsUrl];
    if (result == null) return Colors.grey;
    return result.ok ? Colors.green : Colors.red;
  }

  Future<void> _pickCustom() async {
    final value = await Utils.showEditTextDialog(
      SignalRService.configuredUrl,
      title: "自定义同步服务地址",
      hintText: SignalRService.kDefaultUrl,
      validate: (text) {
        final url = text.trim();
        if (url.isEmpty) return true;
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == "wss" || uri.scheme == "ws") ||
            uri.host.isEmpty) {
          SmartDialog.showToast("请输入 ws:// 或 wss:// 开头的同步服务地址");
          return false;
        }
        return true;
      },
    );
    if (value == null) return;
    if (mounted) Navigator.of(context).pop(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final configured = SignalRService.configuredUrl;
    return AlertDialog(
      title: const Text("选择同步站点"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "探测按当前同步代理配置进行；workers.dev 站点需代理，国内站点可直连。",
              style: Get.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            AppStyle.vGap8,
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final preset in SignalRService.kServerPresets) ...[
                      ListTile(
                        title: Text(preset.label),
                        subtitle: Text(
                          "${preset.note}\n${_statusText(preset.wsUrl)}",
                          style: Get.textTheme.bodySmall,
                        ),
                        isThreeLine: true,
                        trailing: preset.wsUrl == configured
                            ? const Icon(Icons.check)
                            : Icon(
                                Icons.circle,
                                size: 12,
                                color: _statusColor(preset.wsUrl),
                              ),
                        onTap: () => Navigator.of(context).pop(preset.wsUrl),
                      ),
                      AppStyle.divider,
                    ],
                    ListTile(
                      title: const Text("自定义地址…"),
                      subtitle: const Text("输入 ws:// 或 wss:// 开头的地址"),
                      trailing: SignalRService.presetForUrl(configured) == null
                          ? const Icon(Icons.check)
                          : null,
                      onTap: _pickCustom,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("取消"),
        ),
      ],
    );
  }
}
