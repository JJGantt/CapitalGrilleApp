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
        let rows: [[String: Any]] = events.map { e in
            var r: [String: Any] = [
                "timestamp": iso.string(from: e.timestamp),
                "interaction_id": e.interactionId.uuidString,
                "kind": e.kind
            ]
            if let v = e.sessionId    { r["session_id"]   = v }
            if let v = e.backend      { r["backend"]      = v }
            if let v = e.toolName     { r["tool_name"]    = v }
            if let v = e.input        { r["input"]        = v }
            if let v = e.output       { r["output"]       = v }
            if let v = e.error        { r["error"]        = v }
            if let v = e.latencyMs    { r["latency_ms"]   = v }
            if let v = e.tokensIn     { r["tokens_in"]    = v }
            if let v = e.tokensOut    { r["tokens_out"]   = v }
            if let v = e.userInput    { r["user_input"]   = v }
            if let v = e.finalAnswer  { r["final_answer"] = v }
            return r
        }
        do {
            try await SupabaseClient.shared.upsert(path: "app_logs", body: rows, onConflict: "id")
        } catch {
            // Logging must never crash anything. Swallow.
        }
    }
}
