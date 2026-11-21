import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class XiaohongshuDiscoveryRelayPage extends StatefulWidget {
  const XiaohongshuDiscoveryRelayPage({super.key});

  @override
  State<XiaohongshuDiscoveryRelayPage> createState() =>
      _XiaohongshuDiscoveryRelayPageState();
}

class _XiaohongshuDiscoveryRelayPageState
    extends State<XiaohongshuDiscoveryRelayPage> with WidgetsBindingObserver {
  late final String _pairingCode;
  List<String> _addresses = const [];
  bool _loadingAddresses = true;
  bool _sharingAllowed = false;
  bool _routeVisible = false;

  SyncService get _sync => SyncService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pairingCode = _sync.startXiaohongshuDiscoveryRelay();
    _sharingAllowed = _allowsSharing(WidgetsBinding.instance.lifecycleState);
    _sync.setXiaohongshuDiscoveryForeground(_sharingAllowed);
    unawaited(_refreshAddresses());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final allowed = _allowsSharing(state);
    if (_sharingAllowed == allowed) return;
    _sharingAllowed = allowed;
    _sync.setXiaohongshuDiscoveryForeground(allowed);
    if (mounted) setState(() {});
  }

  bool _allowsSharing(AppLifecycleState? state) {
    // A desktop window can lose focus while its sharing page stays open.
    if (GetPlatform.isDesktop) return state != AppLifecycleState.detached;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.stopXiaohongshuDiscoveryRelay();
    super.dispose();
  }

  Future<void> _refreshAddresses() async {
    final addresses = await _sync.getLanIPv4Addresses();
    if (!mounted) return;
    setState(() {
      _addresses = addresses;
      _loadingAddresses = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final routeIsCurrent = ModalRoute.isCurrentOf(context) == true;
    if (_routeVisible != routeIsCurrent) {
      _routeVisible = routeIsCurrent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sync.setXiaohongshuDiscoveryPageVisible(routeIsCurrent);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('小红书直播发现')),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          SettingsCard(
            child: Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('局域网地址', style: Theme.of(context).textTheme.titleMedium),
                  AppStyle.vGap8,
                  if (_loadingAddresses)
                    const Center(child: CircularProgressIndicator())
                  else if (_addresses.isEmpty)
                    const Text('未检测到可连接的局域网 IPv4 地址，请确认本机已连接局域网。')
                  else
                    for (final address in _addresses)
                      SelectableText(
                        '$address:${SyncService.httpPort}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _refreshAddresses,
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新地址'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppStyle.vGap12,
          SettingsCard(
            child: Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Column(
                children: [
                  Text('连接码', style: Theme.of(context).textTheme.titleMedium),
                  AppStyle.vGap8,
                  SelectableText(
                    _pairingCode,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                        ),
                  ),
                  AppStyle.vGap8,
                  const Text(
                    '在电视上输入此六位连接码。关闭页面后连接码失效。',
                    textAlign: TextAlign.center,
                  ),
                  AppStyle.vGap8,
                  Obx(() {
                    if (!_sync.httpRunning.value) {
                      final error = _sync.httpErrorMsg.value.trim();
                      return Text(
                          error.isEmpty ? '局域网服务未启动，请重试或检查端口占用。' : error);
                    }
                    final serving = _sharingAllowed && _routeVisible;
                    return Text(
                      serving ? '直播列表共享已开启' : '直播列表共享暂不可用，请打开此页面。',
                      textAlign: TextAlign.center,
                    );
                  }),
                ],
              ),
            ),
          ),
          AppStyle.vGap12,
          Text(
            GetPlatform.isDesktop
                ? '电脑和电视需在同一局域网。保持此页面打开，电视即可刷新和翻页。'
                : '手机和电视需在同一局域网。离开此页面或将应用切到后台后，服务会暂停。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
