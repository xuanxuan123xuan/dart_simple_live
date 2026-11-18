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
                    .task { await core.start() }
            } else {
                UsageNoticeView {
                    acceptedNoticeVersion = UsageNoticeView.version
                }
            }
        }
    }
}
