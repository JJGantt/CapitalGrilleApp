import SwiftUI

@main
struct CapitalGrilleWatchApp: App {
    @StateObject private var extendedSession = ExtendedSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(extendedSession)
        }
    }
}
