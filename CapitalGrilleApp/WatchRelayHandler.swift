#if os(iOS)
import WatchConnectivity
import Foundation

/// Receives ask requests from the Apple Watch and relays them through
/// MacClient (HTTP → Tailscale → Mac server). Activate once at iOS app launch.
final class WatchRelayHandler: NSObject, WCSessionDelegate {
    static let shared = WatchRelayHandler()

    private override init() { super.init() }

    static func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = shared
        WCSession.default.activate()
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let type = message["type"] as? String, type == "ask" else {
            replyHandler(["error": "missing or unknown type"])
            return
        }
        guard let question = message["question"] as? String,
              let systemPrompt = message["system_prompt"] as? String,
              let sessionId = message["session_id"] as? String else {
            replyHandler(["error": "missing fields"])
            return
        }
        let mode = (message["mode"] as? String) ?? "watch"
        let rawHistory = message["history"] as? [[String: String]] ?? []
        let history = rawHistory.map { (question: $0["question"] ?? "", answer: $0["answer"] ?? "") }

        Task {
            do {
                let answer = try await MacClient.ask(
                    question: question,
                    history: history,
                    systemPrompt: systemPrompt,
                    mode: mode,
                    sessionId: sessionId
                )
                replyHandler(["answer": answer])
            } catch {
                replyHandler(["error": error.localizedDescription])
            }
        }
    }

    // Required WCSessionDelegate stubs (iOS-only)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}
}
#endif
