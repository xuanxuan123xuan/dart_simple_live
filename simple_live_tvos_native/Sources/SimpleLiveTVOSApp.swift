import SwiftUI

@main
struct SimpleLiveTVOSApp: App {
    @StateObject private var core = NativeCoreClient()
    @AppStorage("simple_live_tvos.acceptedNoticeVersion") private var acceptedNoticeVersion = 0

    var body: some Scene {
        WindowGroup {
            if acceptedNoticeVersion >= UsageNoticeView.version {
                HomeView()
                    .environmentObject(core)
                    .toggleStyle(ChineseStatusToggleStyle())
                    .task { await core.start() }
            } else {
                UsageNoticeView {
                    acceptedNoticeVersion = UsageNoticeView.version
                }
            }
        }
    }
}

private struct ChineseStatusToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let status = configuration.isOn ? Text("开") : Text("关")

        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                status
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(status)
    }
}
