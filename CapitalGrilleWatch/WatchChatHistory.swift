import Foundation

final class WatchChatHistory: ObservableObject {
    let sessionId = UUID().uuidString
    private(set) var pairs: [(q: String, a: String)] = []

    func append(q: String, a: String) {
        pairs.append((q: q, a: a))
        if pairs.count > 10 { pairs.removeFirst() }
    }

    func clear() { pairs.removeAll() }
}
