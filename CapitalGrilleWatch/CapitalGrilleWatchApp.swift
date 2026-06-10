import SwiftUI

@main
struct CapitalGrilleWatchApp: App {
    @StateObject private var workoutSession = WorkoutSessionManager()

    init() {
        APIKeyStore.seedFromSecretsIfNeeded()
        // Force WatchPhoneRelay to spin up so it activates WCSession early
        // and picks up any applicationContext (including the API key) the
        // phone has already pushed.
        _ = WatchPhoneRelay.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workoutSession)
        }
    }
}
