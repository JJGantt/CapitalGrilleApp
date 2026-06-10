import Foundation

/// Conversation history that survives watch app restarts.
///
/// Persisted to UserDefaults — small, reliable, no file I/O ceremony. The watch
/// app gets killed aggressively by watchOS, so keeping this purely in-memory
/// caused fresh sessions to lose all context. UserDefaults survives kills and
/// reboots.
final class WatchChatHistory: ObservableObject {
    private(set) var sessionId: String
    private(set) var pairs: [(q: String, a: String)] = []

    private static let pairsKey   = "chatHistoryPairs"
    private static let sessionKey = "chatHistorySessionId"
    private static let maxPairs   = 40

    init() {
        let d = UserDefaults.standard
        self.sessionId = d.string(forKey: Self.sessionKey) ?? {
            let new = UUID().uuidString
            d.set(new, forKey: Self.sessionKey)
            return new
        }()
        if let data = d.data(forKey: Self.pairsKey),
           let stored = try? JSONDecoder().decode([Pair].self, from: data) {
            self.pairs = stored.map { (q: $0.q, a: $0.a) }
        }
    }

    func append(q: String, a: String) {
        objectWillChange.send()
        pairs.append((q: q, a: a))
        if pairs.count > Self.maxPairs { pairs.removeFirst() }
        persist()
    }

    func clear() {
        objectWillChange.send()
        pairs.removeAll()
        // Start a new session id too so the model treats it as a fresh chat.
        sessionId = UUID().uuidString
        let d = UserDefaults.standard
        d.set(sessionId, forKey: Self.sessionKey)
        d.removeObject(forKey: Self.pairsKey)
    }

    private func persist() {
        let stored = pairs.map { Pair(q: $0.q, a: $0.a) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.pairsKey)
    }

    /// Codable shape — tuples aren't Codable, hence the wrapper.
    private struct Pair: Codable {
        let q: String
        let a: String
    }
}
