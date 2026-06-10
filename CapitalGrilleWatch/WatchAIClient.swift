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
            surfaceHint: """
            The answer will be read on an Apple Watch — a screen the size of a postage stamp. Plain text only — no markdown, no headers, no bullet characters.

            START WITH THE ANSWER. Never narrate your own process ("Let me check the menu…", "Looking that up…"). Never state what something is NOT before answering ("X isn't on our menu, but the classic recipe is…"). Never recap the question. Never hedge. Just answer.

            If the user asks for a list (ingredients, components, options), give the actual list, one item per line. If they ask a one-fact question, give one sentence. Length matches what the answer requires — never pad, never substitute a summary for a list when components were asked for.
            """
        )
        let mapped = history.map { (question: $0.q, answer: $0.a) }
        return try await engine.ask(question: prompt, history: mapped, sessionId: sessionId, onActivity: onActivity)
    }
}
