import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';

class KuaishouAccountPage extends GetView<AccountController> {
  const KuaishouAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('快手账号')),
      body: ListView(
        padding: AppStyle.pagePadding(top: 0),
        children: [
          Obx(
            () => ListTile(
              leading: Image.asset(
                'assets/images/kuaishou.png',
                width: 36,
                height: 36,
              ),
              title: const Text('快手直播'),
              subtitle: Text(controller.getKuaishouCookieSummaryText()),
            ),
          ),
          const Divider(height: 1),
          Obx(
            () => ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('主账号'),
              subtitle: Text(
                controller.getKuaishouSlotSummaryText(
                  KuaishouAccountSlot.primary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => controller.kuaishouSlotLogin(
                KuaishouAccountSlot.primary,
              ),
            ),
          ),
          Obx(
            () => ListTile(
              leading: const Icon(Icons.person_add_alt_outlined),
              title: const Text('备用账号'),
              subtitle: Text(
                controller.getKuaishouSlotSummaryText(
                  KuaishouAccountSlot.secondary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => controller.kuaishouSlotLogin(
                KuaishouAccountSlot.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
