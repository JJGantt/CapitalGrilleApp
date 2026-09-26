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
    @ObservedObject private var capture = VoiceCapture.shared
    /// The `app_logs` interaction the recording under way belongs to (`VoiceLog`).
    @State private var voiceId = UUID()

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
                .ignoresSafeArea(edges: .top)
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
        .overlay {
            ZStack {
                // Double tap is the press: start, then send (`press`). It needs a control to bind to,
                // and there is none on screen, so this is one: a point of nothing.
                Button(action: press) { Color.clear.frame(width: 1, height: 1) }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction)
                    .disabled(chatState == .thinking)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // While recording, the whole glass is the press, and the x at the bottom throws it away.
                if capture.recording {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: press)
                        .ignoresSafeArea()
                    VStack {
                        Spacer()
                        Button(action: cancelRecording) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.15)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                    .ignoresSafeArea(edges: .bottom)
                }
                VoiceBorder(state: borderState)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if menuStore.menu == nil { menuStore.load() }
            await bottleStore.refreshFromSupabase()
            await restockStore.refresh()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch chatState {
        case .idle:
            if history.pairs.isEmpty {
                Button(action: press) {
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
                    .contentShape(Rectangle())
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
                    .onTapGesture(coordinateSpace: .global) { at in
                        if at.y > WKInterfaceDevice.current().screenBounds.height / 2 { press() }
                    }
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
                // History scrolls up under the clock row; the idle prompt above
                // keeps the top safe area so the screen's corner doesn't clip it.
                .ignoresSafeArea(edges: .top)
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

    private var borderState: VoiceBorder.State {
        if capture.recording { return .recording }
        return chatState == .thinking ? .working : .idle
    }

    /// **The one press**: the first starts a recording, the next sends it. Only a press ends it.
    private func press() {
        guard chatState != .thinking else { return }
        if capture.recording {
            stopRecording()
        } else {
            errorMsg = nil
            voiceId = UUID()
            let id = voiceId
            capture.start(onTaken: stopRecording) { error in
                errorMsg = error.localizedDescription
                VoiceLog.record("voice_mic_failed", id: id, sessionId: history.sessionId,
                                error: String(describing: error), ends: true)
            }
        }
    }

    private func cancelRecording() {
        guard capture.recording else { return }
        capture.cancel()
        VoiceLog.record("voice_cancelled", id: voiceId, sessionId: history.sessionId, ends: true)
        WKInterfaceDevice.current().play(.failure)
    }

    /// Ends the recording, has the hub transcribe it, and asks the question.
    private func stopRecording() {
        guard let clip = capture.stop() else { return }
        WKInterfaceDevice.current().play(.stop)
        let id = voiceId
        let session = history.sessionId
        let bytes = (try? FileManager.default.attributesOfItem(atPath: clip.url.path)[.size] as? Int) ?? nil
        VoiceLog.record("voice_recorded", id: id, sessionId: session, output: bytes.map { "\($0) bytes" },
                        latencyMs: Int(clip.duration * 1000))
        chatState = .thinking
        errorMsg = nil
        activity = nil
        currentTask = Task {
            defer { try? FileManager.default.removeItem(at: clip.url) }
            let sent = Date()
            func elapsed() -> Int { Int(Date().timeIntervalSince(sent) * 1000) }
            do {
                let words = try await Transcriber.transcribe(clip)
                if Task.isCancelled {
                    VoiceLog.record("voice_cancelled", id: id, sessionId: session, output: words,
                                    latencyMs: elapsed(), ends: true)
                    return
                }
                guard !words.isEmpty else {
                    VoiceLog.record("voice_empty", id: id, sessionId: session, latencyMs: elapsed(), ends: true)
                    chatState = .idle
                    currentTask = nil
                    WKInterfaceDevice.current().play(.failure)
                    return
                }
                VoiceLog.record("voice_transcribed", id: id, sessionId: session, output: words, latencyMs: elapsed())
                currentTask = nil
                send(prompt: words, interactionId: id)
            } catch {
                VoiceLog.record("voice_transcribe_failed", id: id, sessionId: session,
                                error: String(describing: error), latencyMs: elapsed(), ends: true)
                if !Task.isCancelled { errorMsg = error.localizedDescription }
                chatState = .idle
                currentTask = nil
            }
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

    private func send(prompt: String, interactionId: UUID = UUID()) {
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
                    interactionId: interactionId,
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
