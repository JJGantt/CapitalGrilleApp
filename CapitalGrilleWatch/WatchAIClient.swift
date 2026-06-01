import Foundation

/// Thin wrapper around ChatEngine for the watch. Keeps Backend / model
/// selection identical to the iOS app via the shared Backend / AIModel enums.
@MainActor
enum WatchAIClient {
    static func send(prompt: String,
                     history: [(q: String, a: String)],
                     sessionId: String,
                     menuStore: MenuStore,
                     bottleStore: BottleStore,
                     restockStore: RestockStore,
                     onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> String {
        let engine = ChatEngine(
            menuStore: menuStore,
            bottleStore: bottleStore,
            restockStore: restockStore,
            surface: "watch",
            surfaceHint: "The answer will be read on an Apple Watch — a screen the size of a postage stamp. Plain text only — no markdown, no headers, no bullet characters. Cut transitions, hedges, and recap. BUT: 'terse' never means dropping the actual answer. If the user asks for a list (ingredients, components, options, comparisons), give the actual list, one item per line. Length should match what the question requires — a one-fact question gets one sentence; a five-ingredient question gets five lines. Never substitute a summary for a list when components were asked for."
        )
        let mapped = history.map { (question: $0.q, answer: $0.a) }
        return try await engine.ask(question: prompt, history: mapped, sessionId: sessionId, onActivity: onActivity)
    }
}
