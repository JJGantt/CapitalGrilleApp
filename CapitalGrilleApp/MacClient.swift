import Foundation

/// Sends Q&A requests to the Mac (via Tailscale) where `claude -p` runs the model
/// and consumes Max-plan credits instead of API spend.
struct MacClient {
    static let baseURL = URL(string: "http://100.106.101.57:8766")!

    enum MacError: LocalizedError {
        case http(Int, String)
        case decode
        var errorDescription: String? {
            switch self {
            case .http(let c, let body): return "Mac HTTP \(c): \(body.prefix(300))"
            case .decode: return "Couldn't read Mac server response."
            }
        }
    }

    static func ask(question: String,
                    history: [(question: String, answer: String)],
                    systemPrompt: String,
                    mode: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/ask"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let body: [String: Any] = [
            "question": question,
            "history": history.map { ["question": $0.question, "answer": $0.answer] },
            "system_prompt": systemPrompt,
            "mode": mode
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MacError.decode }
        guard (200..<300).contains(http.statusCode) else {
            throw MacError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = json["answer"] as? String else {
            throw MacError.decode
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort liveness check.
    static func isReachable() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("/health"))
        req.timeoutInterval = 2
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch { return false }
    }
}

/// Backend selection. Persisted across launches via UserDefaults.
enum Backend: String, CaseIterable {
    case mac = "mac"        // Claude Code on Mac (Max plan credits — free)
    case api = "api"        // Direct Anthropic API (paid)

    static var current: Backend {
        get {
            let raw = UserDefaults.standard.string(forKey: "backend") ?? Backend.mac.rawValue
            return Backend(rawValue: raw) ?? .mac
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "backend") }
    }
}
