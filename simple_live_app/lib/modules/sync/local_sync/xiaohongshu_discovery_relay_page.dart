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
  bool _foreground = false;
  bool _routeVisible = false;

  SyncService get _sync => SyncService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pairingCode = _sync.startXiaohongshuDiscoveryRelay();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _sync.setXiaohongshuDiscoveryForeground(_foreground);
    unawaited(_refreshAddresses());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync.setXiaohongshuDiscoveryForeground(_foreground);
    if (mounted) setState(() {});
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
                    const Text('未检测到可连接的局域网 IPv4 地址，请确认手机已连接 Wi-Fi。')
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
                    final serving = _foreground && _routeVisible;
                    return Text(
                      serving ? '手机连接已开启' : '手机连接暂不可用，请保持此页面在前台。',
                      textAlign: TextAlign.center,
                    );
                  }),
                ],
              ),
            ),
          ),
          AppStyle.vGap12,
          const Text(
            '手机和电视需在同一局域网。离开此页面或将应用切到后台后，服务会暂停。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
