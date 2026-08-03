import UIKit
import Flutter

/// 自定义 FlutterViewController：状态栏隐藏由 Flutter channel 动态驱动。
///
/// iOS 26 上 `UIViewControllerBasedStatusBarAppearance=false` + `setStatusBarHidden`
/// 在转场动画结束后失效（系统改用 scene-based 状态栏管理并重置）。恢复
/// VC-based 查询：重写 `prefersStatusBarHidden` 动态返回，并调用
/// `setNeedsStatusBarAppearanceUpdate()` 通知系统重新查询——与视图控制器
/// 生命周期深度集成，避免全局设置的时序问题（DevGex 2025 推荐方案）。
class SimpleLiveFlutterViewController: FlutterViewController {
    /// 由 Flutter 侧 simple_live/status_bar channel 设置
    private var statusBarHidden = false

    override var prefersStatusBarHidden: Bool {
        return statusBarHidden
    }

    /// 设置隐藏状态并通知系统重新查询 prefersStatusBarHidden
    func setStatusBarHidden(_ hidden: Bool) {
        statusBarHidden = hidden
        setNeedsStatusBarAppearanceUpdate()
    }
}
