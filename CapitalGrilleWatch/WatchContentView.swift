import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var extendedSession: ExtendedSessionManager

    var body: some View {
        TabView {
            NavigationStack { WatchChatView() }
            NavigationStack { WatchRestockView() }
            NavigationStack { WatchSettingsView() }
        }
        .tabViewStyle(.page)
        .onAppear { extendedSession.start() }
    }
}
