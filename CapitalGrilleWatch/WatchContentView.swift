import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var workoutSession: WorkoutSessionManager

    var body: some View {
        TabView {
            NavigationStack { WatchChatView() }
            NavigationStack { WatchRestockView() }
            NavigationStack { WatchSettingsView() }
        }
        .tabViewStyle(.page)
        .onAppear { workoutSession.start() }
    }
}
