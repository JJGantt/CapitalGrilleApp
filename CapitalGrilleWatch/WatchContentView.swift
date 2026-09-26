import SwiftUI

struct WatchContentView: View {
    var body: some View {
        TabView {
            NavigationStack { WatchChatView() }
            NavigationStack { WatchRestockView() }
            NavigationStack { WatchSettingsView() }
        }
        .tabViewStyle(.page)
    }
}
