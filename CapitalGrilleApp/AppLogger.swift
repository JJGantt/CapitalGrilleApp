import Foundation

/// Fire-and-forget logger that buffers events during a user interaction and POSTs
/// the batch to Supabase after the response is returned. Never blocks the user path.
actor AppLogger {
    static let shared = AppLogger()

    struct Event {
        let timestamp: Date
        let interactionId: UUID
        let sessionId: String?
        let backend: String?
        let kind: String          // "interaction" | "api_request" | "api_error" | "tool_call" | "tool_error" | "fallback"
        let toolName: String?
        let input: Any?           // JSON-serializable
        let output: String?
        let error: String?
        let latencyMs: Int?
        let tokensIn: Int?
        let tokensOut: Int?
        let userInput: String?
        let finalAnswer: String?
    }

    private var buffers: [UUID: [Event]] = [:]

    func record(_ event: Event) {
        buffers[event.interactionId, default: []].append(event)
    }

    /// Detach a fire-and-forget Task that POSTs the buffered events for this interaction.
    /// Removes the buffer immediately so it can't be flushed twice.
    func flush(_ interactionId: UUID) {
        guard let events = buffers.removeValue(forKey: interactionId), !events.isEmpty else { return }
        Task.detached(priority: .background) {
            await Self.post(events: events)
        }
    }

    private static func post(events: [Event]) async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // PostgREST rejects a bulk insert unless every object has the same keys
        // (PGRST102), and one interaction's events fill different fields — an
        // api_request has tokens, a tool_call has a tool name. So every row names
        // every column, with JSON null where this event has no value.
        func orNull(_ value: Any?) -> Any { value ?? NSNull() }
        let rows: [[String: Any]] = events.map { e in
            [
                "timestamp":      iso.string(from: e.timestamp),
                "interaction_id": e.interactionId.uuidString,
                "kind":           e.kind,
                "session_id":     orNull(e.sessionId),
                "backend":        orNull(e.backend),
                "tool_name":      orNull(e.toolName),
                "input":          orNull(e.input),
                "output":         orNull(e.output),
                "error":          orNull(e.error),
                "latency_ms":     orNull(e.latencyMs),
                "tokens_in":      orNull(e.tokensIn),
                "tokens_out":     orNull(e.tokensOut),
                "user_input":     orNull(e.userInput),
                "final_answer":   orNull(e.finalAnswer),
            ]
        }
        do {
            try await SupabaseClient.shared.upsert(path: "app_logs", body: rows, onConflict: "id")
        } catch {
            // Logging must never crash anything. Swallow.
        }
    }
}
