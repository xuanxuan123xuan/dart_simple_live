import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var iosMenuChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Flutter 3.22 的插件注册方式。上游 52318b3 改用的
    // FlutterImplicitEngineDelegate / didInitializeImplicitFlutterEngine 是
    // Flutter 3.35+ 才有的 API,本分支钉在 3.22,需用此经典注册方式。
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "simple_live/live_notifications",
        binaryMessenger: controller.binaryMessenger
      )
      iosMenuChannel = FlutterMethodChannel(
        name: "simple_live/ios_menu",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "showLiveStart" {
          let args = call.arguments as? [String: Any]
          let title = args?["title"] as? String ?? "特别关注开播了"
          let body = args?["body"] as? String ?? "点击回到 Simple Live"
          self.showLiveStartNotification(title: title, body: body)
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // 状态栏隐藏：SystemChrome 在 iOS 26 转场动画后被 scene-based 管理重置。
      // LiveContainer 的 rootViewController 是 FlutterViewController 基类实例，
      // 不能用子类 cast（会失败导致 channel 不注册、app 启动崩溃）。
      // 统一走 setStatusBarHidden 全局控制 + 周期重试对抗系统恢复。
      let statusBarChannel = FlutterMethodChannel(
        name: "simple_live/status_bar",
        binaryMessenger: controller.binaryMessenger
      )
      statusBarChannel.setMethodCallHandler { call, result in
        if call.method == "setHidden" {
          let hidden = (call.arguments as? Bool) ?? false
          DispatchQueue.main.async {
            Self.applyStatusBar(hidden: hidden, retries: 0)
          }
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      let appIconChannel = FlutterMethodChannel(
        name: "simple_live/app_icon",
        binaryMessenger: controller.binaryMessenger
      )
      appIconChannel.setMethodCallHandler { call, result in
        guard call.method == "setIcon" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(
            code: "APP_ICON_UNSUPPORTED",
            message: "This device does not support alternate app icons.",
            details: nil
          ))
          return
        }
        let args = call.arguments as? [String: Any]
        let icon = args?["icon"] as? String
        // The primary icon is AppIcon, which resolves to AppIcon.icon on
        // iOS 26+ (Liquid Glass) and to AppIcon.appiconset below that. Modern
        // therefore means "no alternate". actool requires the .icon bundle and
        // the catalog's primary set to share a name, so both are AppIcon.
        let alternateIconName: String? =
          (icon == "modern" || icon == "simplelive") ? nil : "AppIconSimpleLive"
        if UIApplication.shared.alternateIconName == alternateIconName {
          result(nil)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.setAlternateIconName(alternateIconName) { error in
            if let error = error {
              result(FlutterError(
                code: "APP_ICON_SWITCH_FAILED",
                message: error.localizedDescription,
                details: nil
              ))
            } else {
              result(nil)
            }
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func buildMenu(with builder: UIMenuBuilder) {
    super.buildMenu(with: builder)
    guard builder.system == .main else { return }
    builder.remove(menu: .file)
    builder.insertSibling(makeFileMenu(), beforeMenu: .edit)
    builder.insertSibling(makeNavigationMenu(), afterMenu: .window)
    builder.insertSibling(makeHelpMenu(), afterMenu: .window)
  }

  private func makeFileMenu() -> UIMenu {
    UIMenu(title: "文件", image: UIImage(systemName: "folder"), identifier: .file, options: [], children: [
      UIKeyCommand(title: "配置包导入/导出", action: #selector(openProfileBackup), input: "p", modifierFlags: .command),
    ])
  }

  private func makeNavigationMenu() -> UIMenu {
    UIMenu(title: "导航", image: UIImage(systemName: "sidebar.left"), identifier: UIMenu.Identifier("simple_live.navigation"), options: .displayInline, children: [
      UIKeyCommand(title: "首页", action: #selector(openHome), input: "1", modifierFlags: .command),
      UIKeyCommand(title: "关注", action: #selector(openFollow), input: "2", modifierFlags: .command),
      UIKeyCommand(title: "搜索", action: #selector(openSearch), input: "f", modifierFlags: [.command, .shift]),
      UIKeyCommand(title: "观看历史", action: #selector(openHistory), input: "h", modifierFlags: [.command, .shift]),
    ])
  }

  private func makeHelpMenu() -> UIMenu {
    UIMenu(title: "帮助", image: UIImage(systemName: "questionmark.circle"), identifier: UIMenu.Identifier("simple_live.help"), options: .displayInline, children: [
      UIKeyCommand(title: "设置", action: #selector(openSettings), input: ",", modifierFlags: .command),
      UIKeyCommand(title: "使用帮助", action: #selector(openHelp), input: "?", modifierFlags: .command),
      UIKeyCommand(title: "关于 Simple Live", action: #selector(openAbout), input: "a", modifierFlags: [.command, .shift]),
      UIKeyCommand(title: "检查更新", action: #selector(openUpdate), input: "u", modifierFlags: [.command, .shift]),
    ])
  }

  private func invokeMenu(_ name: String) {
    iosMenuChannel?.invokeMethod(name, arguments: nil)
  }

  @objc private func openHome(_ sender: Any?) { invokeMenu("openHome") }
  @objc private func openFollow(_ sender: Any?) { invokeMenu("openFollow") }
  @objc private func openSearch(_ sender: Any?) { invokeMenu("openSearch") }
  @objc private func openHistory(_ sender: Any?) { invokeMenu("openHistory") }
  @objc private func openSettings(_ sender: Any?) { invokeMenu("openSettings") }
  @objc private func openHelp(_ sender: Any?) { invokeMenu("openHelp") }
  @objc private func openAbout(_ sender: Any?) { invokeMenu("openAbout") }
  @objc private func openUpdate(_ sender: Any?) { invokeMenu("openUpdate") }
  @objc private func openProfileBackup(_ sender: Any?) { invokeMenu("openProfileBackup") }

  /// 强制状态栏隐藏/显示。iOS 26 上 setStatusBarHidden 可能被系统忽略，
  /// 周期重试 5 次对抗系统恢复；同时刷新所有窗口 VC 外观（兼容 VC-based 路径）。
  /// 注意：不在此处做视觉遮罩（黑条）——LiveContainer 下 safeArea/statusBarFrame
  /// 不可靠，遮罩会盖住弹幕且退出全屏残留。状态栏隐藏依赖签名版 SystemChrome。
  static func applyStatusBar(hidden: Bool, retries: Int) {
    UIApplication.shared.setStatusBarHidden(hidden, with: .none)
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
          top = presented
        }
        top?.setNeedsStatusBarAppearanceUpdate()
      }
    }
    if retries < 5 {
      let delays = [0.4, 0.8, 1.4, 2.2, 3.0]
      DispatchQueue.main.asyncAfter(deadline: .now() + delays[retries]) {
        Self.applyStatusBar(hidden: hidden, retries: retries + 1)
      }
    }
  }

  private func showLiveStartNotification(title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: "simple_live_live_start_\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
      center.add(request, withCompletionHandler: nil)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

}
