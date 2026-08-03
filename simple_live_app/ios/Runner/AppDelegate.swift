import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
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

      // iOS 26 + LiveContainer 下 SystemChrome 隐藏状态栏失效（引擎未适配
      // scene-based 状态栏管理，容器 VC 层级进一步覆盖）。走原生强制隐藏：
      // UIViewControllerBasedStatusBarAppearance=false 后系统改用
      // UIApplication.setStatusBarHidden 全局控制，绕过 VC appearance 查询。
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
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 强制状态栏隐藏/显示。iOS 26 上 setStatusBarHidden 可能被系统忽略，
  /// 周期重试 3 次对抗系统恢复；同时刷新所有窗口 VC 外观（兼容 VC-based 路径）。
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
    if retries < 3 {
      let delays = [0.5, 1.0, 1.5]
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
