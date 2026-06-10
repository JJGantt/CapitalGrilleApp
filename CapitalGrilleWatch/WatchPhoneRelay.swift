#if os(watchOS)
import WatchConnectivity
import Foundation

/// Sends ask requests from the watch to the phone, which then forwards through
/// MacClient (HTTP → Tailscale → Mac server). The watch itself can't reach the
/// Mac directly because watchOS doesn't participate in the Tailscale tunnel.
@MainActor
final class WatchPhoneRelay: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchPhoneRelay()

    @Published private(set) var isReachable = false

    private var pending: [String: CheckedContinuation<String, Error>] = [:]

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            // Pick up a key the phone may have pushed in a previous session.
            ingestContext(WCSession.default.receivedApplicationContext)
        }
    }

    private func ingestContext(_ ctx: [String: Any]) {
        if let key = ctx["anthropic_api_key"] as? String, !key.isEmpty {
            _ = APIKeyStore.set(key)
        }
    }

    func relay(question: String,
               history: [(question: String, answer: String)],
               systemPrompt: String,
               mode: String,
               sessionId: String) async throws -> String {
        guard WCSession.default.isReachable else { throw RelayError.notReachable }

        return try await withCheckedThrowingContinuation { cont in
            let id = UUID().uuidString
            pending[id] = cont
            let hist = history.map { ["question": $0.question, "answer": $0.answer] }
            WCSession.default.sendMessage(
                [
                    "type": "ask",
                    "id": id,
                    "question": question,
                    "history": hist,
                    "system_prompt": systemPrompt,
                    "mode": mode,
                    "session_id": sessionId,
                ],
                replyHandler: { [weak self] reply in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let answer = reply["answer"] as? String {
                            pending.removeValue(forKey: id)?.resume(returning: answer)
                        } else {
                            let msg = reply["error"] as? String ?? "Unknown error from phone"
                            pending.removeValue(forKey: id)?.resume(throwing: RelayError.phoneError(msg))
                        }
                    }
                },
                errorHandler: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.pending.removeValue(forKey: id)?.resume(throwing: error)
                    }
                }
            )
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.ingestContext(applicationContext) }
    }

    enum RelayError: LocalizedError {
        case notReachable, phoneError(String)
        var errorDescription: String? {
            switch self {
            case .notReachable:      return "iPhone not reachable. Switching to API."
            case .phoneError(let m): return m
            }
        }
    }
}
#endif
