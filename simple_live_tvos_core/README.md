# SimpleLiveTVOSCore

此 Swift 包包含与平台无关的 tvOS 业务状态和协议模型，
不导入 Flutter、SwiftUI、UIKit、WebKit 或 KSPlayer。

tvOS 原生应用负责将这些类型与 `simple_live_core`、KSPlayer、Keychain
和 SwiftUI 对接。xtool 可以在 Windows/Linux 上准备 Swift 工具链，
并运行此包的 SwiftPM 测试。此包不负责构建 tvOS 应用。
