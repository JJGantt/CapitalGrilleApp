import Foundation

/// Sends Q&A requests to the Mac where `claude -p` runs the model and consumes
/// Max-plan credits instead of API spend.
///
/// Real device → Tailscale (works from anywhere on cellular/WiFi).
/// Simulator → localhost on the same Mac. Same server, same MCP, same code path —
/// only the network hop differs. Simulator-via-Tailscale hangs in sandboxed iOS
/// processes; this avoids that.
struct MacClient {
    static let baseURL: URL = {
#if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8766")!
#else
        return URL(string: "http://100.106.101.57:8766")!
#endif
    }()

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
                    mode: String,
                    sessionId: String,
                    onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> String {
        // Stream by default if a handler is provided, otherwise use the simple endpoint.
        if onActivity != nil {
            return try await askStream(question: question, history: history,
                                       systemPrompt: systemPrompt, mode: mode,
                                       sessionId: sessionId,
                                       onActivity: onActivity!)
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("/ask"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let body: [String: Any] = [
            "question": question,
            "history": history.map { ["question": $0.question, "answer": $0.answer] },
            "system_prompt": systemPrompt,
            "mode": mode,
            "model": AIModel.current.rawValue,
            "session_id": sessionId
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

    private static func askStream(question: String,
                                  history: [(question: String, answer: String)],
                                  systemPrompt: String,
                                  mode: String,
                                  sessionId: String,
                                  onActivity: @escaping @MainActor (String?) -> Void) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/ask/stream"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let body: [String: Any] = [
            "question": question,
            "history": history.map { ["question": $0.question, "answer": $0.answer] },
            "system_prompt": systemPrompt,
            "mode": mode,
            "model": AIModel.current.rawValue,
            "session_id": sessionId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MacError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }

        var finalAnswer = ""
        var textBuf = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst("data: ".count))
            guard let data = payload.data(using: .utf8),
                  let ev = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = ev["type"] as? String else { continue }
            switch type {
            case "tool_use":
                let name = (ev["name"] as? String) ?? ""
                let input = ev["input"] ?? [:]
                let inputJSON = (try? String(data: JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted]), encoding: .utf8)) ?? "{}"
                let activity = "\(name)(\(inputJSON))"
                await MainActor.run { onActivity(activity) }
            case "text_delta":
                if let txt = ev["text"] as? String { textBuf += txt }
            case "done":
                if let a = ev["answer"] as? String, !a.isEmpty {
                    finalAnswer = a
                } else {
                    finalAnswer = textBuf
                }
            case "error":
                throw MacError.http(500, (ev["message"] as? String) ?? "stream error")
            default: break
            }
        }
        await MainActor.run { onActivity(nil) }
        return finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
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

enum AIModel: String, CaseIterable, Identifiable {
    case haiku  = "claude-haiku-4-5"
    case sonnet = "claude-sonnet-4-6"
    case opus   = "claude-opus-4-7"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .haiku:  return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus:   return "Opus"
        }
    }

    static var current: AIModel {
        get {
            let raw = UserDefaults.standard.string(forKey: "model") ?? AIModel.sonnet.rawValue
            return AIModel(rawValue: raw) ?? .sonnet
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "model") }
    }
}
