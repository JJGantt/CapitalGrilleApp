import Foundation

enum AnthropicError: LocalizedError {
    case noAPIKey
    case requestFailed(String)
    case decodeFailed
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key set. Open Settings to add one."
        case .requestFailed(let s): return "Request failed: \(s)"
        case .decodeFailed: return "Couldn't read response."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

struct AnthropicClient {
    static let model = "claude-haiku-4-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"

    /// Send a message in a multi-turn conversation about the entire menu.
    /// `history` is the prior exchanges; `question` is the new user message.
    static func chat(question: String, history: [(question: String, answer: String)], menuJSON: String) async throws -> String {
        let apiKey = Secrets.anthropicAPIKey
        guard apiKey.hasPrefix("sk-ant") else {
            throw AnthropicError.noAPIKey
        }

        let system = """
        You are a quick reference assistant for The Capital Grille bartender/server training. Below is the complete menu data (JSON) — dishes, prices, ingredients, portions, prep, talking points, etc. Use this to answer questions accurately.

        Be concise — 1-3 sentences unless the user asks for a list or detail. If a question can be answered from the data, do so. If not, say so plainly rather than guessing.

        MENU DATA:
        \(menuJSON)
        """

        var messages: [[String: Any]] = []
        for ex in history {
            messages.append(["role": "user", "content": ex.question])
            messages.append(["role": "assistant", "content": ex.answer])
        }
        messages.append(["role": "user", "content": question])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 800,
            "system": system,
            "messages": messages
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AnthropicError.requestFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "?"
            throw AnthropicError.httpError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AnthropicError.decodeFailed
        }
        // Concatenate text blocks
        let text = content.compactMap { ($0["text"] as? String) }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
