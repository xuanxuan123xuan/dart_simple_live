import CoreImage.CIFilterBuiltins
import SwiftUI

struct ProviderLoginView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var status = "正在获取二维码"
    @State private var attempt = 0
    @State private var canRetry = false
    let provider: ProviderDescriptor

    var body: some View {
        VStack(spacing: 28) {
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 340, height: 340)
                    .padding(24)
                    .background(.white)
                    .accessibilityLabel("\(provider.title)登录二维码")
            } else if !canRetry {
                ProgressView()
            }
            Text(status)
            if canRetry { Button("刷新二维码") { attempt += 1 } }
            Button("取消", action: { dismiss() })
        }
        .navigationTitle("\(provider.title)扫码登录")
        .task(id: attempt) { await login() }
    }

    private func login() async {
        image = nil
        canRetry = false
        status = "正在获取二维码"
        do {
            let challenge = try await core.loginChallenge(provider: provider.id)
            try Task.checkCancellation()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(challenge.url.absoluteString.utf8)
            guard let output = filter.outputImage,
                  let code = CIContext().createCGImage(output, from: output.extent) else {
                throw LiveProviderError.invalidResponse
            }
            image = code
            status = "请使用\(provider.title) App 扫码"
            while true {
                try await Task.sleep(for: .seconds(3))
                switch try await core.pollLogin(challenge, provider: provider.id) {
                case .waiting: break
                case .scanned: status = "已扫码，请在手机上确认"
                case let .authorized(cookie):
                    try await core.finishLogin(cookie: cookie, provider: provider.id)
                    dismiss()
                    return
                }
            }
        } catch {
            if !Task.isCancelled {
                status = error.localizedDescription
                image = nil
                canRetry = true
            }
        }
    }
}
