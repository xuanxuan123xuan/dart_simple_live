import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/kuaishou_account_service.dart';
import 'package:simple_live_tv_app/services/signalr_service.dart';

class SettingsController extends BaseController
    with GetTickerProviderStateMixin {
  late TabController tabController;
  var tabIndex = 0.obs;

  SettingsController() {
    tabController = TabController(length: 6, vsync: this);
    tabController.animation?.addListener(() {
      var currentIndex = (tabController.animation?.value ?? 0).round();
      if (tabIndex.value == currentIndex) {
        return;
      }
      tabIndex.value = currentIndex;
      if (tabIndex.value == 0) {
        hardwareDecodeFocusNode.requestFocus();
      }
      if (tabIndex.value == 1) {
        danmakuFoucsNode.requestFocus();
      }
      if (tabIndex.value == 2) {
        autoUpdateFollowEnableFocusNode.requestFocus();
      }
      if (tabIndex.value == 3) {
        multiRoomGapFocusNode.requestFocus();
      }
      if (tabIndex.value == 4) {
        bilibiliFoucsNode.requestFocus();
      }
      if (tabIndex.value == 5) {
        versionFocusNode.requestFocus();
      }
    });
  }
  var hardwareDecodeFocusNode = AppFocusNode()..isFoucsed.value = true;
  var compatibleModeFocusNode = AppFocusNode();
  var mpvProfileFocusNode = AppFocusNode();
  var scaleFoucsNode = AppFocusNode();
  var defaultQualityFocusNode = AppFocusNode();
  var danmakuFoucsNode = AppFocusNode();
  var danmakuSizeFoucsNode = AppFocusNode();
  var danmakuEmojiFoucsNode = AppFocusNode();
  var danmakuSpeedFoucsNode = AppFocusNode();
  var danmakuAreaFoucsNode = AppFocusNode();
  var danmakuOpacityFoucsNode = AppFocusNode();
  var danmakuStorkeFoucsNode = AppFocusNode();
  var liveEventFlowFoucsNode = AppFocusNode();
  var liveEventFlowOverlayFoucsNode = AppFocusNode();
  var liveEventFlowWindowFoucsNode = AppFocusNode();
  var liveEventFlowDisplayFoucsNode = AppFocusNode();
  var liveEventFlowMinCountFoucsNode = AppFocusNode();
  var danmakuDedupeFoucsNode = AppFocusNode();
  var danmakuDedupeModeFoucsNode = AppFocusNode();
  var danmakuDedupeWindowFoucsNode = AppFocusNode();
  var danmakuDedupeStepFoucsNode = AppFocusNode();

  var autoUpdateFollowEnableFocusNode = AppFocusNode();
  var autoUpdateFollowDurationFocusNode = AppFocusNode();
  var updateFollowThreadFocusNode = AppFocusNode();
  var followPageSizeFocusNode = AppFocusNode();
  var multiRoomGapFocusNode = AppFocusNode();

  var bilibiliFoucsNode = AppFocusNode();
  var kuaishouFocusNode = AppFocusNode();
  var versionFocusNode = AppFocusNode();

  void editSyncServerUrl() async {
    var value = await Utils.showEditTextDialog(
      SignalRService.configuredUrl,
      title: "同步服务地址",
      hintText: SignalRService.kDefaultUrl,
      validate: (text) {
        final url = text.trim();
        if (url.isEmpty) {
          return true;
        }
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
    if (value == null) {
      return;
    }
    await SignalRService.setConfiguredUrl(value);
    SmartDialog.showToast(value.trim().isEmpty ? "已恢复默认同步服务" : "已保存");
    update();
  }

  void editSyncProxyUrl() async {
    var value = await Utils.showEditTextDialog(
      SignalRService.configuredProxyUrl,
      title: "同步代理地址",
      hintText: "TV 端请填局域网代理，例如 192.168.1.2:51888",
      validate: (text) {
        final value = text.trim();
        if (!SignalRService.isValidProxyConfig(value)) {
          SmartDialog.showToast("请输入 host:port、http://host:port，或 direct 直连");
          return false;
        }
        return true;
      },
    );
    if (value == null) {
      return;
    }
    await SignalRService.setConfiguredProxyUrl(value);
    SmartDialog.showToast(value.trim().isEmpty ? "已恢复自动检测代理" : "已保存");
    update();
  }

  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      AppNavigator.toBiliBiliLogin();
    }
  }

  void douyinTap() async {
    final hasCookie = DouyinAccountService.instance.hasCookie.value;
    final action = await Utils.showOptionDialog<String>(
      [
        "编辑或导入 Cookie",
        if (hasCookie) "查看当前 Cookie",
        if (hasCookie) "导出到剪贴板",
        if (hasCookie) "清除 Cookie",
      ],
      "编辑或导入 Cookie",
      title: "抖音账号",
    );
    switch (action) {
      case "编辑或导入 Cookie":
        await _editDouyinCookie();
        break;
      case "查看当前 Cookie":
        await _showCurrentDouyinCookie();
        break;
      case "导出到剪贴板":
        await _exportDouyinCookieToClipboard();
        break;
      case "清除 Cookie":
        await _clearDouyinCookie();
        break;
      default:
        break;
    }
  }

  Future<void> _editDouyinCookie() async {
    final current = DouyinAccountService.instance.cookie;
    final value = await Utils.showEditTextDialog(
      current,
      title: "抖音 Cookie",
      hintText: "粘贴完整 Cookie，留空则恢复默认 ttwid",
    );
    if (value == null) {
      return;
    }
    final input = value.trim();
    if (input.isEmpty) {
      DouyinAccountService.instance.clearCookie();
      SmartDialog.showToast("已清除自定义抖音 Cookie");
      update();
      return;
    }
    final cookie = DouyinCookieHelper.normalizeInput(input);
    DouyinAccountService.instance.setCookie(cookie);
    SmartDialog.showToast(
      DouyinCookieHelper.hasFullCookie(cookie) ? "抖音 Cookie 已保存" : "已保存 ttwid",
    );
    update();
  }

  Future<void> _showCurrentDouyinCookie() async {
    final cookie = DouyinAccountService.instance.cookie;
    if (cookie.isEmpty) {
      SmartDialog.showToast("当前没有自定义抖音 Cookie");
      return;
    }
    await Utils.showMessageDialog(
      cookie,
      title: "当前抖音 Cookie",
      selectable: true,
    );
  }

  Future<void> _exportDouyinCookieToClipboard() async {
    final cookie = DouyinAccountService.instance.cookie;
    if (cookie.isEmpty) {
      SmartDialog.showToast("当前没有自定义抖音 Cookie");
      return;
    }
    await Clipboard.setData(ClipboardData(text: cookie));
    SmartDialog.showToast("已复制当前抖音 Cookie");
  }

  Future<void> _clearDouyinCookie() async {
    final confirmed = await Utils.showAlertDialog(
      "确定要清除自定义抖音 Cookie 吗？",
      title: "清除配置",
    );
    if (!confirmed) {
      return;
    }
    DouyinAccountService.instance.clearCookie();
    SmartDialog.showToast("已清除自定义抖音 Cookie");
    update();
  }

  Future<void> kuaishouTap() async {
    final action = await Utils.showOptionDialog<String>(
      const ["管理主账号", "管理备用账号"],
      "管理主账号",
      title: "快手账号池",
    );
    switch (action) {
      case "管理主账号":
        await _manageKuaishouSlot(KuaishouAccountSlot.primary);
        break;
      case "管理备用账号":
        await _manageKuaishouSlot(KuaishouAccountSlot.secondary);
        break;
      default:
        break;
    }
  }

  Future<void> _manageKuaishouSlot(KuaishouAccountSlot slot) async {
    final session = KuaishouAccountService.instance.sessionFor(slot);
    final action = await Utils.showOptionDialog<String>(
      [
        "编辑或导入 Cookie",
        if (session.isConfigured) "查看当前 Cookie",
        if (session.isConfigured) "导出到剪贴板",
        if (session.isConfigured) "清除 Cookie",
      ],
      "编辑或导入 Cookie",
      title: "快手${_kuaishouSlotName(slot)}",
    );
    switch (action) {
      case "编辑或导入 Cookie":
        await _editKuaishouCookie(slot);
        break;
      case "查看当前 Cookie":
        await _showCurrentKuaishouCookie(slot);
        break;
      case "导出到剪贴板":
        await _exportKuaishouCookie(slot);
        break;
      case "清除 Cookie":
        await _clearKuaishouCookie(slot);
        break;
      default:
        break;
    }
  }

  Future<void> _editKuaishouCookie(KuaishouAccountSlot slot) async {
    final account = KuaishouAccountService.instance;
    final session = account.sessionFor(slot);
    final value = await Utils.showEditTextDialog(
      session.cookie,
      title: "快手${_kuaishouSlotName(slot)} Cookie",
      hintText: "粘贴 live.kuaishou.com 的完整 Cookie 或 Request Headers",
      maxLines: 6,
    );
    if (value == null) return;

    final cookie = normalizeKuaishouCookieInput(value);
    if (cookie.isEmpty) {
      account.clearCookieForSlot(slot);
      SmartDialog.showToast("已清除快手${_kuaishouSlotName(slot)} Cookie");
      update();
      return;
    }
    final saved = account.setCookieForSlot(
      slot,
      cookie,
      kww: extractKuaishouKwwFromInput(value),
    );
    if (!saved) {
      SmartDialog.showToast("主账号和备用账号不能使用相同 Cookie 或 UID");
      return;
    }
    SmartDialog.showToast(
      kuaishouCookieHasKey(cookie, "kwfv1")
          ? "快手 Cookie 已保存"
          : "Cookie 已保存；缺少 kwfv1 时弹幕可能不可用",
    );
    update();
  }

  Future<void> _showCurrentKuaishouCookie(KuaishouAccountSlot slot) async {
    final cookie = KuaishouAccountService.instance.sessionFor(slot).cookie;
    if (cookie.isEmpty) {
      SmartDialog.showToast("当前没有快手 Cookie");
      return;
    }
    await Utils.showMessageDialog(
      cookie,
      title: "快手${_kuaishouSlotName(slot)} Cookie",
      selectable: true,
    );
  }

  Future<void> _exportKuaishouCookie(KuaishouAccountSlot slot) async {
    final cookie = KuaishouAccountService.instance.sessionFor(slot).cookie;
    if (cookie.isEmpty) {
      SmartDialog.showToast("当前没有快手 Cookie");
      return;
    }
    await Clipboard.setData(ClipboardData(text: cookie));
    SmartDialog.showToast("已复制快手${_kuaishouSlotName(slot)} Cookie");
  }

  Future<void> _clearKuaishouCookie(KuaishouAccountSlot slot) async {
    final confirmed = await Utils.showAlertDialog(
      "确定要清除快手${_kuaishouSlotName(slot)} Cookie 吗？",
      title: "清除配置",
    );
    if (!confirmed) return;
    KuaishouAccountService.instance.clearCookieForSlot(slot);
    SmartDialog.showToast("已清除快手${_kuaishouSlotName(slot)} Cookie");
    update();
  }

  String getKuaishouAccountSummaryText() {
    final account = KuaishouAccountService.instance;
    account.revision.value;
    account.mode.value;
    final configured = [
      account.primary,
      account.secondary,
    ].where((session) => session.isConfigured).length;
    return "当前：${_kuaishouModeName(account.mode.value)}；"
        "已配置 $configured/2，异常时自动切换";
  }

  String getKuaishouSlotSummaryText(KuaishouAccountSlot slot) {
    final account = KuaishouAccountService.instance;
    account.revision.value;
    final session = account.sessionFor(slot);
    if (!session.isConfigured) return "未配置";
    final now = DateTime.now();
    if (session.credentialState == KuaishouCredentialState.invalid) {
      return "已失效，请重新配置";
    }
    if (session.suspendedUntil?.isAfter(now) == true) {
      return "请求受限，已暂停";
    }
    if (session.cooldownUntil?.isAfter(now) == true) {
      return "请求冷却中";
    }
    return session.credentialState == KuaishouCredentialState.valid
        ? "有效"
        : "已配置，待验证";
  }

  String _kuaishouSlotName(KuaishouAccountSlot slot) =>
      slot == KuaishouAccountSlot.primary ? "主账号" : "备用账号";

  String _kuaishouModeName(KuaishouAccountPoolMode mode) => switch (mode) {
    KuaishouAccountPoolMode.primary => "主账号",
    KuaishouAccountPoolMode.secondary => "备用账号",
    KuaishouAccountPoolMode.anonymous => "匿名模式",
  };
}

String normalizeKuaishouCookieInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return "";
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final item = line.trim();
    if (item.toLowerCase().startsWith("cookie:")) {
      return item.substring(item.indexOf(":") + 1).trim();
    }
  }
  return text;
}

String extractKuaishouKwwFromInput(String input) {
  for (final line in input.trim().split(RegExp(r'\r?\n'))) {
    final item = line.trim();
    final lower = item.toLowerCase();
    for (final name in const ["kww", "kwfv1"]) {
      if (lower.startsWith("$name:") || lower.startsWith("$name=")) {
        return item.substring(name.length + 1).trim();
      }
    }
  }
  return "";
}

bool kuaishouCookieHasKey(String cookie, String key) {
  final expected = key.toLowerCase();
  return cookie.split(';').any((part) {
    final item = part.trim();
    final separator = item.indexOf('=');
    return separator > 0 &&
        item.substring(0, separator).trim().toLowerCase() == expected;
  });
}
