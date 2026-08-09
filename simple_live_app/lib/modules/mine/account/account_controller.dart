import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/account/douyin_cookie_display.dart';
import 'package:simple_live_app/routes/account_route_target.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AccountController extends GetxController {
  static const _douyinHomeUrl = "https://www.douyin.com/";
  static const _kuaishouHomeUrl = "https://live.kuaishou.com/";

  final douyinCookieCountdownTick = 0.obs;
  Timer? _douyinCookieCountdownTimer;

  @override
  void onInit() {
    super.onInit();
    _douyinCookieCountdownTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => douyinCookieCountdownTick.value++,
    );
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments == AccountRouteTarget.douyinCookieConfig) {
      doDouyinCookieConfig();
    }
  }

  @override
  void onClose() {
    _douyinCookieCountdownTimer?.cancel();
    super.onClose();
  }

  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      //AppNavigator.toBiliBiliLogin();
      bilibiliLogin();
    }
  }

  void bilibiliLogin() {
    Utils.showBottomSheet(
      title: "登录哔哩哔哩",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS || Utils.isOhos,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("填写用户名密码登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kBiliBiliWebLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text("扫码登录"),
            subtitle: const Text("使用哔哩哔哩APP扫描二维码登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kBiliBiliQRLogin);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动输入Cookie登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doBiliBiliCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void doBiliBiliCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入Cookie",
      hintText: "请输入Cookie",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    BiliBiliAccountService.instance.setCookie(cookie);
    await BiliBiliAccountService.instance.loadUserInfo();
  }

  void douyinTap() async {
    douyinLogin();
  }

  void kuaishouTap() async {
    kuaishouLogin();
  }

  void douyinLogin() {
    final hasCookie = DouyinAccountService.instance.hasCookie.value;
    Utils.showBottomSheet(
      title: "抖音账号",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Platform.isAndroid || Platform.isIOS || Utils.isOhos)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('网页登录'),
              subtitle: const Text('在应用内登录抖音并自动保存 Cookie'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await Get.toNamed(RoutePath.kDouyinWebLogin);
              },
            ),
          if (!Platform.isAndroid && !Platform.isIOS && !Utils.isOhos)
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text("浏览器登录后粘贴 Cookie"),
              subtitle: const Text("使用系统浏览器打开抖音，登录后回到这里粘贴完整 Cookie"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await openDouyinInBrowserThenConfigCookie();
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动粘贴自己的 www.douyin.com 完整 Cookie"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doDouyinCookieConfig();
            },
          ),
          if (hasCookie)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text("查看当前 Cookie"),
              subtitle: const Text("可直接查看当前保存内容"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                showCurrentDouyinCookie();
              },
            ),
          if (hasCookie)
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text("导出到剪贴板"),
              subtitle: const Text("复制当前 Cookie 文本"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                exportDouyinCookieToClipboard();
              },
            ),
          if (Platform.isAndroid || Platform.isIOS || Utils.isOhos)
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text("从文件导入 Cookie"),
              subtitle: const Text("选择电脑传到手机上的 txt/cookie 文件"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await importDouyinCookieFromFile();
              },
            ),
          if (DouyinAccountService.instance.hasCookie.value)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text("清除 Cookie"),
              subtitle: const Text("清除后恢复默认 ttwid"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await clearDouyinCookie();
              },
            ),
        ],
      ),
    );
  }

  Future<void> clearDouyinCookie() async {
    if (DouyinAccountService.instance.hasCookie.value) {
      var result =
          await Utils.showAlertDialog("确定要清除自定义抖音 Cookie 吗？", title: "清除配置");
      if (result) {
        DouyinAccountService.instance.clearCookie();
        douyinCookieCountdownTick.value++;
        SmartDialog.showToast("已清除自定义 Cookie，将使用默认 ttwid");
      }
    }
  }

  void kuaishouLogin() {
    kuaishouSlotLogin(KuaishouAccountSlot.primary);
  }

  void kuaishouSlotLogin(KuaishouAccountSlot slot) {
    final session = KuaishouAccountService.instance.sessionFor(slot);
    final hasCookie = session.isConfigured;
    Utils.showBottomSheet(
      title: "快手${getKuaishouSlotName(slot)}",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Platform.isAndroid || Platform.isIOS || Utils.isOhos)
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("登录快手网页后自动读取 Cookie"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                kuaishouWebLogin(slot);
              },
            ),
          if (!Platform.isAndroid && !Platform.isIOS && !Utils.isOhos)
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text("浏览器登录后粘贴 Cookie"),
              subtitle: const Text("使用系统浏览器打开快手直播，登录后回到这里粘贴完整 Cookie"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await openKuaishouInBrowserThenConfigCookie(slot);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动粘贴 live.kuaishou.com 完整 Cookie"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doKuaishouCookieConfig(slot);
            },
          ),
          if (hasCookie)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text("查看当前 Cookie"),
              subtitle: const Text("可直接查看当前保存内容"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                showCurrentKuaishouCookie(slot);
              },
            ),
          if (hasCookie)
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text("导出到剪贴板"),
              subtitle: const Text("复制当前 Cookie 文本"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                exportKuaishouCookieToClipboard(slot);
              },
            ),
          if (Platform.isAndroid || Platform.isIOS || Utils.isOhos)
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text("从文件导入 Cookie"),
              subtitle: const Text("选择电脑传到手机上的 txt/cookie 文件"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await importKuaishouCookieFromFile(slot);
              },
            ),
          if (hasCookie)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text("清除 Cookie"),
              subtitle: const Text("清除后快手搜索和弹幕可能受限"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Get.back();
                await clearKuaishouCookie(slot);
              },
            ),
        ],
      ),
    );
  }

  bool get canUseKuaishouWebLogin =>
      Platform.isAndroid || Platform.isIOS || Utils.isOhos;

  void kuaishouWebLogin([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) {
    Get.toNamed(RoutePath.kKuaishouWebLogin, arguments: slot);
  }

  Future<void> clearKuaishouCookie([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) async {
    final account = KuaishouAccountService.instance;
    if (account.sessionFor(slot).isConfigured) {
      final result = await Utils.showAlertDialog(
        "确定要清除快手${getKuaishouSlotName(slot)} Cookie 吗？",
        title: "清除配置",
      );
      if (result) {
        account.clearCookieForSlot(slot);
        SmartDialog.showToast("已清除快手${getKuaishouSlotName(slot)} Cookie");
      }
    }
  }

  void doKuaishouCookieConfig([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) {
    final account = KuaishouAccountService.instance;
    final session = account.sessionFor(slot);
    final cookieController = TextEditingController(text: session.cookie);
    Utils.showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: Text("配置快手${getKuaishouSlotName(slot)} Cookie"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "只需粘贴完整 Cookie 或 Request Headers，不需要填写 Kww。应用会优先使用 Cookie 中的 kwfv1 自动生成弹幕签名。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cookieController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: "Cookie",
                  hintText: "粘贴 live.kuaishou.com 的完整 Cookie",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("取消")),
          TextButton(
            onPressed: () {
              final rawInput = cookieController.text;
              final cookie = _normalizeCookieInput(rawInput);
              final pastedKww = _extractKuaishouKww(rawInput);
              Get.back();
              if (cookie.isEmpty) {
                account.clearCookieForSlot(slot);
                SmartDialog.showToast(
                  "已清除快手${getKuaishouSlotName(slot)} Cookie",
                );
              } else {
                final saved = account.setCookieForSlot(
                  slot,
                  cookie,
                  kww: pastedKww,
                );
                if (!saved) {
                  SmartDialog.showToast("主账号和备用账号不能使用相同 Cookie 或 UID");
                  return;
                }
                final hasKwfv1 = _parseCookieMap(cookie).containsKey("kwfv1");
                SmartDialog.showToast(
                  hasKwfv1 || pastedKww.isNotEmpty
                      ? "快手 Cookie 已保存"
                      : "Cookie 已保存，但缺少 kwfv1，弹幕可能需要重新网页登录",
                );
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    ).whenComplete(cookieController.dispose);
  }

  void showCurrentKuaishouCookie([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) {
    final credentials = _currentKuaishouCredentialsText(slot);
    if (credentials.isEmpty) {
      SmartDialog.showToast("当前没有快手弹幕凭证");
      return;
    }
    Utils.showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: Text("快手${getKuaishouSlotName(slot)}弹幕凭证"),
        content: SingleChildScrollView(child: SelectableText(credentials)),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("关闭")),
          TextButton(
            onPressed: () {
              Utils.copyToClipboard(credentials);
              Get.back();
            },
            child: const Text("复制"),
          ),
        ],
      ),
    );
  }

  void exportKuaishouCookieToClipboard([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) {
    final credentials = _currentKuaishouCredentialsText(slot);
    if (credentials.isEmpty) {
      SmartDialog.showToast("当前没有快手弹幕凭证");
      return;
    }
    Utils.copyToClipboard(credentials);
  }

  Future<void> openKuaishouInBrowserThenConfigCookie([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) async {
    try {
      final opened = await launchUrlString(
        _kuaishouHomeUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        SmartDialog.showToast("无法打开系统浏览器，请手动打开 live.kuaishou.com 后粘贴 Cookie");
      }
    } catch (_) {
      SmartDialog.showToast("无法打开系统浏览器，请手动打开 live.kuaishou.com 后粘贴 Cookie");
    }
    doKuaishouCookieConfig(slot);
  }

  Future<void> importKuaishouCookieFromFile([
    KuaishouAccountSlot slot = KuaishouAccountSlot.primary,
  ]) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final file = picked.files.single;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null && file.path!.isNotEmpty) {
        content = await File(file.path!).readAsString();
      } else {
        SmartDialog.showToast("无法读取所选文件");
        return;
      }
      final cookie = _normalizeCookieInput(content);
      if (cookie.isEmpty) {
        SmartDialog.showToast("Cookie 文件内容为空");
        return;
      }
      final kww = _extractKuaishouKww(content);
      final saved = KuaishouAccountService.instance.setCookieForSlot(
        slot,
        cookie,
        kww: kww,
      );
      SmartDialog.showToast(
        saved
            ? "已从文件导入快手${getKuaishouSlotName(slot)} Cookie"
            : "主账号和备用账号不能使用相同 Cookie 或 UID",
      );
    } catch (e) {
      SmartDialog.showToast("导入 Cookie 失败：$e");
    }
  }

  void showCurrentDouyinCookie() {
    final cookie = DouyinAccountService.instance.cookie;
    if (cookie.isEmpty) {
      SmartDialog.showToast("当前没有自定义抖音 Cookie");
      return;
    }
    Utils.showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: const Text("当前抖音 Cookie"),
        content: SingleChildScrollView(
          child: SelectableText(cookie),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () {
              Utils.copyToClipboard(cookie);
              Get.back();
            },
            child: const Text("复制"),
          ),
        ],
      ),
    );
  }

  void exportDouyinCookieToClipboard() {
    final cookie = DouyinAccountService.instance.cookie;
    if (cookie.isEmpty) {
      SmartDialog.showToast("当前没有自定义抖音 Cookie");
      return;
    }
    Utils.copyToClipboard(cookie);
  }

  Future<void> openDouyinInBrowserThenConfigCookie() async {
    try {
      final opened = await launchUrlString(
        _douyinHomeUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        SmartDialog.showToast("无法打开系统浏览器，请手动打开 www.douyin.com 后粘贴 Cookie");
      }
    } catch (_) {
      SmartDialog.showToast("无法打开系统浏览器，请手动打开 www.douyin.com 后粘贴 Cookie");
    }
    doDouyinCookieConfig();
  }

  Future<void> importDouyinCookieFromFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final file = picked.files.single;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null && file.path!.isNotEmpty) {
        content = await File(file.path!).readAsString();
      } else {
        SmartDialog.showToast("无法读取所选文件");
        return;
      }
      final input = content.trim();
      if (input.isEmpty) {
        SmartDialog.showToast("Cookie 文件内容为空");
        return;
      }
      final cookie = DouyinCookieHelper.normalizeInput(input);
      DouyinAccountService.instance.setCookie(cookie);
      douyinCookieCountdownTick.value++;
      SmartDialog.showToast(
        DouyinCookieDisplay.savedMessage(cookie, imported: true),
      );
    } catch (e) {
      SmartDialog.showToast("导入 Cookie 失败：$e");
    }
  }

  void doDouyinCookieConfig() {
    // 兼容旧版只保存 ttwid 的配置。
    var savedCookie = DouyinAccountService.instance.cookie;
    var displayText = savedCookie;
    if (savedCookie.startsWith('ttwid=') && !savedCookie.contains(";")) {
      displayText = savedCookie.substring(6);
    }
    var controller = TextEditingController(text: displayText);
    final expiryText = ValueNotifier(_getDouyinCookieExpiryText(displayText));
    void updateExpiryText() {
      expiryText.value = _getDouyinCookieExpiryText(controller.text);
    }

    controller.addListener(updateExpiryText);
    final timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => updateExpiryText(),
    );

    Utils.showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: const Text("配置抖音 Cookie"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "默认内置 ttwid 可用于播放；房间名/主播名搜索被要求登录时，不能只填 ttwid，需要粘贴登录后的完整 www.douyin.com Cookie。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              const Text(
                "电脑端获取方式：F12 打开开发者工具，在 Network 里点 www.douyin.com 或 live.douyin.com 的请求，复制 Request Headers 里的 Cookie 整行；也可以粘贴请求标头整段，应用会自动提取 Cookie。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: "搜索请粘贴完整 Cookie；只填 ttwid 只能作为播放兜底",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: expiryText,
                builder: (context, value, child) {
                  return Text(
                    value,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  var defaultValue = DouyinSite.kDefaultCookie;
                  if (defaultValue.startsWith('ttwid=')) {
                    defaultValue = defaultValue.substring(6);
                  }
                  controller.text = defaultValue;
                  updateExpiryText();
                },
                icon: const Icon(Icons.restore),
                label: const Text("恢复默认 ttwid"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              var input = controller.text.trim();
              Get.back();
              if (input.isEmpty) {
                DouyinAccountService.instance.clearCookie();
                douyinCookieCountdownTick.value++;
                SmartDialog.showToast("已清除自定义 Cookie，将使用默认 ttwid");
              } else {
                var cookie = DouyinCookieHelper.normalizeInput(input);
                DouyinAccountService.instance.setCookie(cookie);
                douyinCookieCountdownTick.value++;
                SmartDialog.showToast(
                  DouyinCookieDisplay.savedMessage(cookie),
                );
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    ).whenComplete(() {
      timer.cancel();
      controller.removeListener(updateExpiryText);
      controller.dispose();
      expiryText.dispose();
    });
  }

  String getDouyinCookieSummaryText() {
    douyinCookieCountdownTick.value;
    DouyinAccountService.instance.hasCookie.value;
    final cookie = DouyinAccountService.instance.cookie;
    return DouyinCookieDisplay.summary(cookie);
  }

  String _getDouyinCookieExpiryText(String input) {
    final cookie =
        (DouyinCookieHelper.extractCookieFromHeaderText(input) ?? input).trim();
    if (cookie.isEmpty) {
      return "当前使用默认 ttwid，无法判断搜索登录态有效期。";
    }
    if (DouyinCookieHelper.isOnlyTtwid(
        DouyinCookieHelper.normalizeInput(cookie))) {
      return "当前仅为 ttwid，无法判断搜索登录态有效期；主播 / 房间搜索仍可能需要完整 Cookie。";
    }

    if (!DouyinCookieHelper.hasLoginSession(cookie)) {
      return "未检测到登录字段；房间 / 主播搜索仍不可用，请重新复制登录后的完整 Cookie。";
    }

    final expiry = DouyinCookieHelper.parseExpiry(cookie);
    if (expiry == null) {
      return "未从 Cookie 中解析到到期时间；Request Headers 不包含标准 Expires，实际有效期以抖音服务端为准。";
    }

    final remain = expiry.difference(DateTime.now());
    final expireAt = _formatDateTimeMinute(expiry);
    if (remain.isNegative) {
      return "可解析到期时间已过：$expireAt；如果搜索失败，请重新获取 Cookie。";
    }
    return "Cookie 预计剩余 ${_formatDurationShort(remain)}，到期时间 $expireAt；退出登录、改密或风控可能提前失效。";
  }

  Map<String, String> _parseCookieMap(String cookie) {
    final result = <String, String>{};
    for (final part in cookie.split(";")) {
      final item = part.trim();
      if (item.isEmpty) {
        continue;
      }
      final separatorIndex = item.indexOf("=");
      if (separatorIndex <= 0) {
        continue;
      }
      final key = item.substring(0, separatorIndex).trim();
      final value = item.substring(separatorIndex + 1).trim();
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  String getKuaishouCookieSummaryText() {
    douyinCookieCountdownTick.value;
    final account = KuaishouAccountService.instance;
    account.revision.value;
    account.hasCookie.value;
    account.mode.value;
    return "当前模式：${getKuaishouModeName(account.mode.value)}";
  }

  String getKuaishouSlotName(KuaishouAccountSlot slot) =>
      slot == KuaishouAccountSlot.primary ? "主账号" : "备用账号";

  String getKuaishouModeName(KuaishouAccountPoolMode mode) => switch (mode) {
        KuaishouAccountPoolMode.primary => "主账号",
        KuaishouAccountPoolMode.secondary => "备用账号",
        KuaishouAccountPoolMode.anonymous => "匿名模式",
      };

  String getKuaishouSlotSummaryText(KuaishouAccountSlot slot) {
    douyinCookieCountdownTick.value;
    final account = KuaishouAccountService.instance;
    account.revision.value;
    account.mode.value;
    final session = account.sessionFor(slot);
    if (!session.isConfigured) {
      return "未配置";
    }
    final now = DateTime.now();
    if (session.credentialState == KuaishouCredentialState.invalid) {
      return "已失效，请重新登录";
    }
    final suspendedUntil = session.suspendedUntil;
    if (suspendedUntil?.isAfter(now) == true) {
      return "请求频繁，暂停至 ${_formatDateTime(suspendedUntil!)}";
    }
    final cooldownUntil = session.cooldownUntil;
    if (cooldownUntil?.isAfter(now) == true) {
      return "冷却至 ${_formatDateTime(cooldownUntil!)}";
    }

    final state = session.credentialState == KuaishouCredentialState.valid
        ? "有效"
        : "已配置，待验证";
    final expiry = session.cookieExpiresAt;
    if (expiry == null) {
      final loginText = session.loggedInAt == null
          ? ""
          : "，登录于 ${_formatDateTime(session.loggedInAt!)}";
      final validatedText = session.lastValidatedAt == null
          ? ""
          : "，上次验证 ${_formatDateTime(session.lastValidatedAt!)}";
      return "$state，到期时间未知$loginText$validatedText";
    }
    final remain = expiry.difference(now);
    if (remain.isNegative) {
      return "$state，预计已到期";
    }
    return "$state，预计剩余 ${_formatDurationShort(remain)}";
  }

  String _currentKuaishouCredentialsText(KuaishouAccountSlot slot) {
    final cookie = KuaishouAccountService.instance.sessionFor(slot).cookie;
    return cookie.isEmpty ? "" : "Cookie: $cookie";
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return "${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} "
        "${twoDigits(local.hour)}:${twoDigits(local.minute)}";
  }

  String _extractKuaishouKww(String input) {
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

  String _normalizeCookieInput(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return "";
    }
    final lines = text.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final item = line.trim();
      final lower = item.toLowerCase();
      if (lower.startsWith("cookie:")) {
        return item.substring(item.indexOf(":") + 1).trim();
      }
    }
    return text;
  }

  String _formatDurationShort(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    if (days > 0) {
      return "$days 天 $hours 小时";
    }
    if (hours > 0) {
      return "$hours 小时 $minutes 分钟";
    }
    return "${duration.inMinutes} 分钟";
  }

  String _formatDateTimeMinute(DateTime dateTime) {
    String twoDigits(int value) => value.toString().padLeft(2, "0");
    return "${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)} "
        "${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}";
  }
}
