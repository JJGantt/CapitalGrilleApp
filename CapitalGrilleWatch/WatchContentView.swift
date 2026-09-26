import SwiftUI

struct WatchContentView: View {
    @ObservedObject private var capture = VoiceCapture.shared
    @State private var page = 0
    var body: some View {
        TabView(selection: $page) {
            NavigationStack { WatchChatView() }.tag(0)
            NavigationStack { WatchRestockView() }.tag(1)
            NavigationStack { WatchSettingsView() }.tag(2)
        }
        .tabViewStyle(.page)
        // The complication opens the app straight into a recording, on the chat page whichever page
        // was showing.
        .onOpenURL { url in
            guard url.scheme == "capitalgrille", url.host == "record" else { return }
            page = 0
            capture.requestRecording()
        }
    }
}
