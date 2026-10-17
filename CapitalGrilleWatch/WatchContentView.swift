import SwiftUI

struct WatchContentView: View {
    @ObservedObject private var capture = VoiceCapture.shared
    @State private var page = 0
    /// One catalog and one restock list for the chat and the restock page, so an add made by voice is
    /// already on the restock page, and the page never waits on a catalog download of its own.
    @StateObject private var bottleStore = BottleStore()
    @StateObject private var restockStore = RestockStore()
    @StateObject private var orderStore = OrderStore()
    var body: some View {
        TabView(selection: $page) {
            NavigationStack { WatchChatView() }.tag(0).environment(\.onScreen, page == 0)
            // The order list is the owner's alone: it sits behind the hub's owner-gated route.
            if AppGate.isOwnerDevice {
                NavigationStack { WatchOrdersView() }.tag(3).environment(\.onScreen, page == 3)
            }
            NavigationStack { WatchRestockView() }.tag(1)
            NavigationStack { WatchSettingsView() }.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environmentObject(bottleStore)
        .environmentObject(restockStore)
        .environmentObject(orderStore)
        // The complication opens the app straight into a recording, on the chat page whichever page
        // was showing.
        .onOpenURL { url in
            guard url.scheme == "capitalgrille", url.host == "record" else { return }
            page = 0
            capture.requestRecording()
        }
    }
}
