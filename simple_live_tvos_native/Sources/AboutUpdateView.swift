import CoreImage.CIFilterBuiltins
import SwiftUI

struct AboutUpdateView: View {
    private enum CheckState {
        case idle
        case loading
        case noRelease
        case release(TVOSRelease, CGImage?)
        case failed
    }

    private let version: String?
    private let build: String?
    private let releaseService: TVOSReleaseService
    @State private var state = CheckState.idle
    @State private var attempt = 0

    init(bundle: Bundle = .main, releaseService: TVOSReleaseService = .init()) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        self.releaseService = releaseService
    }

    var body: some View {
        HStack(spacing: 80) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("本机版本 \(version ?? "未知")")
                    Text("构建号 \(build ?? "未知")")
                }
                .foregroundStyle(.secondary)

                Button(checkButtonTitle) {
                    if case .loading = state { return }
                    state = .loading
                    attempt += 1
                }
                .accessibilityIdentifier("about-check-update")

                status
                    .frame(minHeight: 100, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            releaseQRCode
                .frame(width: 420)
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("关于和更新")
        .task(id: attempt) {
            if attempt > 0 { await checkForUpdates() }
        }
    }

    private var checkButtonTitle: LocalizedStringKey {
        if case .failed = state { return "重试检查更新" }
        return "检查更新"
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 16) {
                ProgressView()
                Text("正在检查更新")
            }
        case .noRelease:
            Text("暂无稳定的 tvOS 版本")
        case .release(let release, _):
            if let installed = version.flatMap(TVOSVersion.init) {
                if release.version > installed {
                    Text("发现新版本 v\(release.versionName)")
                } else if release.version == installed {
                    Text("已是最新版本")
                } else {
                    Text("本机版本高于最新稳定版本 v\(release.versionName)")
                }
            } else {
                Text("最新稳定版本 v\(release.versionName)")
            }
        case .failed:
            Text("检查更新失败，请重试")
        }
    }

    @ViewBuilder
    private var releaseQRCode: some View {
        if case let .release(_, code) = state {
            if let code {
                VStack(spacing: 20) {
                    Image(code, scale: 1, label: Text("GitHub 发布页二维码"))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 288, height: 288)
                        .padding(32)
                        .background(.white)
                        .accessibilityIdentifier("about-release-qr")
                    Text("请用手机扫码打开 GitHub 发布页")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("无法生成发布页二维码")
            }
        }
    }

    @MainActor
    private func checkForUpdates() async {
        guard !Task.isCancelled else { return }
        do {
            let release = try await releaseService.latestStableRelease()
            try Task.checkCancellation()
            if let release {
                state = .release(release, Self.qrCode(for: release.pageURL))
            } else {
                state = .noRelease
            }
        } catch {
            state = Task.isCancelled ? .idle : .failed
        }
    }

    private static func qrCode(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
