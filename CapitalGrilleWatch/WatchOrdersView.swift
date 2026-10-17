import SwiftUI
import WatchKit

/// **The order list.** Double tap starts a recording of a guest ordering, the next press sends it: the
/// hub transcribes it, `OrderTaker` turns it into menu items, and they land at the top of the list. The
/// clip is deleted once it is transcribed; only the text is kept.
///
/// Rows work like the restock list's: a tap arms one (red), a second tap marks it done and it leaves the
/// list. Clear all at the bottom takes two presses.
///
/// Owner only (`WatchContentView`): the list sits behind the hub's owner-gated route.
struct WatchOrdersView: View {
    @EnvironmentObject private var store: OrderStore
    @EnvironmentObject private var bottleStore: BottleStore
    @StateObject private var menuStore = MenuStore()
    @StateObject private var cocktailStore = CocktailStore()
    @ObservedObject private var capture = VoiceCapture.shared
    @Environment(\.onScreen) private var onScreen
    @Environment(\.scenePhase) private var phase

    @State private var working = false
    @State private var task: Task<Void, Never>?
    @State private var armedID: String?
    @State private var clearArmed = false
    @State private var errorMsg: String?
    /// The `app_logs` interaction the recording under way belongs to (`VoiceLog`).
    @State private var voiceId = UUID()
    private let sessionId = "orders"

    private static let top: CGFloat = 32

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Orders")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    ForEach(store.orders) { order in
                        row(order)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(armedID == order.id ? Color.red.opacity(0.35) : Color.clear))
                    }
                    if !store.orders.isEmpty {
                        clearAllButton.padding(.top, 10)
                    }
                    if let err = errorMsg ?? store.loadError {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .padding(8)
                    }
                }
                .padding(.top, Self.top)
                .padding(.horizontal, 4)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .ignoresSafeArea(edges: .top)
        }
        .overlay {
            ZStack {
                // Double tap is the press: start, then send. Bound only while this page is showing, since
                // the chat page binds it too.
                Button(action: press) { Color.clear.frame(width: 1, height: 1) }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction)
                    .disabled(!onScreen || working)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if capture.recording {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: press)
                        .ignoresSafeArea()
                }
                if capture.recording || working {
                    VStack {
                        Spacer()
                        Button(action: capture.recording ? cancelRecording : cancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(VoiceBorder.red)
                                .frame(width: 72, height: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                    .ignoresSafeArea(edges: .bottom)
                }
                VoiceBorder(state: capture.recording ? .recording : working ? .working : .idle)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: working) { _, now in StayAwake.shared.set(now) }
        .onChange(of: phase) { _, now in if now == .active && onScreen { Task { await store.refresh() } } }
        .onChange(of: onScreen) { _, now in if now { Task { await store.refresh() } } }
        .task {
            if menuStore.menu == nil { menuStore.load() }
            if cocktailStore.cocktails.isEmpty { cocktailStore.load() }
            // The chat page loads the catalog on launch; an order taken before that lands needs it too,
            // or every bottle id is refused.
            if bottleStore.bottles.isEmpty { await bottleStore.refreshFromSupabase() }
            await store.refresh()
        }
    }

    @ViewBuilder
    private func row(_ order: Order) -> some View {
        Button { tap(order) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(order.qty > 1 ? "\(order.qty)× \(order.name)" : order.name)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    if let note = order.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if armedID == order.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var clearAllButton: some View {
        Button {
            if clearArmed {
                clearArmed = false
                WKInterfaceDevice.current().play(.click)
                Task { await store.clearAll() }
            } else {
                clearArmed = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    clearArmed = false
                }
            }
        } label: {
            Text(clearArmed ? "Confirm" : "Clear all")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(clearArmed ? VoiceBorder.red : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tap(_ order: Order) {
        if armedID == order.id {
            armedID = nil
            WKInterfaceDevice.current().play(.click)
            Task { await store.done(order.id) }
        } else {
            armedID = order.id
            let armed = order.id
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if armedID == armed { armedID = nil }
            }
        }
    }

    // MARK: recording

    private func press() {
        guard !working else { return }
        if capture.recording {
            send()
        } else {
            errorMsg = nil
            voiceId = UUID()
            let id = voiceId
            capture.start(onTaken: send) { error in
                errorMsg = error.localizedDescription
                VoiceLog.record("voice_mic_failed", id: id, sessionId: sessionId, error: String(describing: error), ends: true)
            }
        }
    }

    private func cancelRecording() {
        guard capture.recording else { return }
        capture.cancel()
        VoiceLog.record("voice_cancelled", id: voiceId, sessionId: sessionId, ends: true)
        WKInterfaceDevice.current().play(.failure)
    }

    private func cancel() {
        task?.cancel()
        task = nil
        working = false
        WKInterfaceDevice.current().play(.failure)
    }

    /// Transcribes the clip (then deletes it), has the model pull the orders out, and lands them.
    private func send() {
        guard let clip = capture.stop() else { return }
        WKInterfaceDevice.current().play(.stop)
        let id = voiceId
        VoiceLog.record("voice_recorded", id: id, sessionId: sessionId, latencyMs: Int(clip.duration * 1000))
        working = true
        errorMsg = nil
        task = Task {
            defer { try? FileManager.default.removeItem(at: clip.url) }
            let sent = Date()
            func elapsed() -> Int { Int(Date().timeIntervalSince(sent) * 1000) }
            do {
                let words = try await Transcriber.transcribe(clip, interactionId: id) { attempt, error in
                    VoiceLog.record("voice_transcribe_retry", id: id, sessionId: sessionId, output: "try \(attempt)",
                                    error: String(describing: error), latencyMs: elapsed())
                }
                try? FileManager.default.removeItem(at: clip.url)
                try Task.checkCancellation()
                guard !words.isEmpty else {
                    VoiceLog.record("voice_empty", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
                    finish(haptic: .failure)
                    return
                }
                VoiceLog.record("voice_transcribed", id: id, sessionId: sessionId, output: words, latencyMs: elapsed())
                let added = try await OrderTaker.take(words, store: store, menu: menuStore.menu,
                                                      bottles: Array(bottleStore.bottles.values),
                                                      cocktails: cocktailStore.cocktails,
                                                      interactionId: id, sessionId: sessionId)
                try Task.checkCancellation()
                VoiceLog.record("orders_added", id: id, sessionId: sessionId, output: "\(added)", latencyMs: elapsed(), ends: true)
                finish(haptic: added > 0 ? .success : .retry)
            } catch is CancellationError {
                VoiceLog.record("voice_cancelled", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
            } catch {
                VoiceLog.record("orders_failed", id: id, sessionId: sessionId, error: String(describing: error),
                                latencyMs: elapsed(), ends: true)
                if !Task.isCancelled {
                    errorMsg = error.localizedDescription
                    finish(haptic: .failure)
                }
            }
        }
    }

    private func finish(haptic: WKHapticType) {
        working = false
        task = nil
        WKInterfaceDevice.current().play(haptic)
    }
}

extension EnvironmentValues {
    /// Whether this page is the one showing. Every page is alive side by side in the TabView, so a page
    /// that binds double tap asks this first.
    @Entry var onScreen: Bool = true
}
