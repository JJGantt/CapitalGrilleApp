import SwiftUI
import WatchKit

struct WatchChatView: View {
    @StateObject private var history = WatchChatHistory()
    @StateObject private var menuStore = MenuStore()
    @StateObject private var bottleStore = BottleStore()
    @StateObject private var restockStore = RestockStore()
    @State private var chatState: ChatState = .idle
    @State private var lastPrompt = ""
    @State private var response = ""
    @State private var errorMsg: String?
    @State private var activity: String?
    @State private var currentTask: Task<Void, Never>?

    enum ChatState { case idle, thinking }

    private let responseAnchor = "response-anchor"

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            mainContent
            // Filled X button — opaque so content scrolling under it stays
            // readable but the X is always prominent. Anchored to the very
            // top-left of the screen.
            if !history.pairs.isEmpty {
                Button(action: clearResponse) {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let err = errorMsg, !lastPrompt.isEmpty {
                VStack {
                    Spacer()
                    Button(action: retry) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(err)
                                .foregroundColor(.red)
                                .font(.system(size: 11))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Tap to retry")
                                .foregroundColor(.white)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            } else if let err = errorMsg {
                VStack {
                    Spacer()
                    Text(err)
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task {
            if menuStore.menu == nil { menuStore.load() }
            await bottleStore.refreshFromSupabase()
            await restockStore.refresh()
        }
    }

    /// Opens system dictation. Double-tap also triggers this hands-free.
    private func dictationLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        TextFieldLink(prompt: Text("Ask the assistant…"), label: label) { text in
            let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return }
            send(prompt: prompt)
        }
        .handGestureShortcut(.primaryAction)
        .disabled(chatState == .thinking)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch chatState {
        case .idle:
            if history.pairs.isEmpty {
                dictationLink {
                    VStack {
                        HStack {
                            Text(">")
                                .foregroundColor(.gray)
                                .font(.system(size: 20, weight: .regular, design: .monospaced))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(history.pairs.enumerated()), id: \.offset) { idx, pair in
                                let isLatest = idx == history.pairs.count - 1
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pair.q)
                                        .foregroundColor(.gray)
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(pair.a)
                                        .foregroundColor(.white)
                                        .font(.system(size: 13))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(isLatest ? responseAnchor : "pair-\(idx)")
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.never)
                    // Reserve a 32pt strip at the top so the newest response
                    // settles below the time + X button row when we scroll to
                    // the responseAnchor.
                    .safeAreaInset(edge: .top) {
                        Color.clear.frame(height: 32)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.none) { proxy.scrollTo(responseAnchor, anchor: .top) }
                        }
                    }
                    .onChange(of: history.pairs.count) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(responseAnchor, anchor: .top) }
                        }
                    }
                }
                .background(
                    // Invisible dictation link so the hand-gesture double-tap
                    // (handGestureShortcut(.primaryAction)) still opens
                    // dictation when history is showing. Not user-tappable —
                    // exists only so the gesture-shortcut has a target.
                    dictationLink { Color.clear }
                        .buttonStyle(.plain)
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .allowsHitTesting(false)
                )
            }

        case .thinking:
            VStack(spacing: 10) {
                ProgressView()
                Text(activity ?? "Thinking…")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                Button(action: cancel) {
                    Label("Cancel", systemImage: "stop.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .tint(.red)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .handGestureShortcut(.primaryAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 6)
        }
    }

    private func cancel() {
        currentTask?.cancel()
        currentTask = nil
        activity = nil
        chatState = .idle
        // Keep lastPrompt so the user can retry after cancelling — e.g. flip
        // backend in Settings, then come back and tap Retry.
        if !lastPrompt.isEmpty {
            errorMsg = "Cancelled"
        }
    }

    private func retry() {
        guard !lastPrompt.isEmpty else { return }
        send(prompt: lastPrompt)
    }

    private func clearResponse() {
        withAnimation(.easeOut(duration: 0.2)) {
            response = ""
            lastPrompt = ""
            errorMsg = nil
            history.clear()
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func send(prompt: String) {
        chatState = .thinking
        errorMsg = nil
        activity = nil
        lastPrompt = prompt
        currentTask = Task {
            do {
                let answer = try await WatchAIClient.send(
                    prompt: prompt,
                    history: history.pairs,
                    sessionId: history.sessionId,
                    menuStore: menuStore,
                    bottleStore: bottleStore,
                    restockStore: restockStore,
                    onActivity: { act in self.activity = act }
                )
                if Task.isCancelled { return }
                history.append(q: prompt, a: answer)
                response = answer
                // Strong two-pulse haptic when the answer lands.
                WKInterfaceDevice.current().play(.notification)
            } catch is CancellationError {
                // user cancelled — silent
            } catch {
                if !Task.isCancelled {
                    errorMsg = error.localizedDescription
                }
            }
            activity = nil
            if chatState == .thinking { chatState = .idle }
            currentTask = nil
        }
    }
}
