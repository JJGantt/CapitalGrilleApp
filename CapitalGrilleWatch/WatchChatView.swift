import SwiftUI

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
        ZStack {
            Color.black.ignoresSafeArea()
            mainContent
            if let err = errorMsg {
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
            if response.isEmpty {
                dictationLink {
                    VStack(spacing: 6) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.accentColor)
                        Text("Double tap to speak")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !lastPrompt.isEmpty {
                                Text(lastPrompt)
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(response)
                                .foregroundColor(.white)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(responseAnchor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 40) // leave room for the floating sparkles
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        // Land with the response at the top; prompt is scrollable above.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.none) { proxy.scrollTo(responseAnchor, anchor: .top) }
                        }
                    }
                    .onChange(of: response) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(responseAnchor, anchor: .top) }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    dictationLink {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
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
