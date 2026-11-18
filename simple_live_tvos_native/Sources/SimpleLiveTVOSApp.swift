import SwiftUI

@main
struct SimpleLiveTVOSApp: App {
    @StateObject private var core = NativeCoreClient()
    @StateObject private var sessionStore = KeychainSessionStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(core)
                .environmentObject(sessionStore)
                .task { await core.start() }
        }
    }
}
