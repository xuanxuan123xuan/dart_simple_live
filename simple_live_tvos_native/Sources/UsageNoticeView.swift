import SwiftUI

struct UsageNoticeView: View {
    static let version = 1

    @State private var declined = false
    @FocusState private var focus: Action?
    let accept: () -> Void

    private enum Action: Hashable {
        case accept, decline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("使用须知")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("欢迎使用 Simple Live TV，请在使用前仔细阅读以下内容：")
            VStack(alignment: .leading, spacing: 12) {
                Text("1. 本软件为开源软件，仅供学习交流使用，禁止用于任何商业用途。")
                Text("2. 本软件不提供直播内容，直播内容来自网络。")
                Text("3. 使用本软件出于个人意愿，请对自己的使用行为和结果负责。")
                Text("4. 如有合法权益受到侵犯，请联系项目维护者处理。")
            }
            HStack(spacing: 28) {
                Button("已阅读并同意", action: accept)
                    .focused($focus, equals: .accept)
                    .accessibilityIdentifier("usage-notice-accept")
                Button("暂不同意") { declined = true }
                    .accessibilityIdentifier("usage-notice-decline")
                    .focused($focus, equals: .decline)
            }
            Text(declined ? "应用仍停留在使用须知。可按遥控器的电视键离开。" : "同意后即可进入 Simple Live。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 1140)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { HomeBackdrop() }
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, .accept)
    }
}
