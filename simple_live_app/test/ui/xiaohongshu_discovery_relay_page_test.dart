import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/sync/local_sync/local_sync_controller.dart';
import 'package:simple_live_app/modules/sync/local_sync/local_sync_page.dart';
import 'package:simple_live_app/services/sync_service.dart';

void main() {
  testWidgets('desktop sharing stays active while the window lacks focus',
      (tester) async {
    Get.testMode = true;
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });
    final service = _TestSyncService();
    Get.put<SyncService>(service);
    Get.put(LocalSyncController(null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const GetMaterialApp(home: LocalSyncPage()));

    await tester.tap(find.text('小红书直播发现'));
    await tester.pumpAndSettle();

    expect(find.text('192.168.1.20:23234'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    expect(service.pageVisible, isTrue);
    expect(service.sharingAllowed, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(service.sharingAllowed, isTrue);
    expect(find.text('直播列表共享已开启'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(service.stopped, isTrue);
  }, skip: !GetPlatform.isDesktop);
}

class _TestSyncService extends SyncService {
  bool pageVisible = false;
  bool sharingAllowed = false;
  bool stopped = false;

  @override
  void initServer() {
    httpRunning.value = true;
  }

  @override
  void listenUDP() {}

  @override
  Future<List<String>> getLanIPv4Addresses() async => ['192.168.1.20'];

  @override
  String startXiaohongshuDiscoveryRelay() => '123456';

  @override
  void setXiaohongshuDiscoveryPageVisible(bool visible) =>
      pageVisible = visible;

  @override
  void setXiaohongshuDiscoveryForeground(bool foreground) =>
      sharingAllowed = foreground;

  @override
  void stopXiaohongshuDiscoveryRelay() => stopped = true;
}
