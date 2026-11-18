import SwiftUI

@main
struct SimpleLiveTVOSApp: App {
    @StateObject private var core = NativeCoreClient()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(core)
                .task { await core.start() }
        }
    }
}
