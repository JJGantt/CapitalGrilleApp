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

/// Tool the model can call. The handler is async and returns a string result that
/// gets fed back as a `tool_result` content block.
struct AnthropicTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    let handler: (_ input: [String: Any]) async throws -> String
}

struct AnthropicClient {
    static var model: String { AIModel.current.rawValue }
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"

    // MARK: - Food (no tools)

    static func chat(question: String, history: [(question: String, answer: String)], menuJSON: String) async throws -> String {
        let system = """
        You are a quick reference assistant for The Capital Grille bartender/server training. Below is the complete menu data (JSON) — dishes, prices, ingredients, portions, prep, talking points, etc. Use this to answer questions accurately.

        Be concise — 1-3 sentences unless the user asks for a list or detail. If a question can be answered from the data, do so. If not, say so plainly rather than guessing.

        MENU DATA:
        \(menuJSON)
        """
        return try await chatWithTools(question: question, history: history, system: system, tools: [])
    }

    // MARK: - General multi-turn with optional tools

    static func chatWithTools(question: String,
                              history: [(question: String, answer: String)],
                              system: String,
                              tools: [AnthropicTool],
                              onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> String {
        let apiKey = Secrets.anthropicAPIKey
        guard apiKey.hasPrefix("sk-ant") else { throw AnthropicError.noAPIKey }

        // Build messages: prior history as plain text, then current user question.
        var messages: [[String: Any]] = []
        for ex in history {
            messages.append(["role": "user", "content": ex.question])
            messages.append(["role": "assistant", "content": ex.answer])
        }
        messages.append(["role": "user", "content": question])

        // Loop: send → if tool_use, run handlers, append results, send again.
        // Cap at a reasonable number of turns to avoid infinite loops.
        var collectedText: [String] = []
        for _ in 0..<6 {
            let response = try await call(apiKey: apiKey, system: system, tools: tools, messages: messages)

            // Capture any plain-text blocks before/after tool_use.
            for block in response.content {
                if let type = block["type"] as? String, type == "text",
                   let text = block["text"] as? String, !text.isEmpty {
                    collectedText.append(text)
                }
            }

            if response.stopReason != "tool_use" {
                break
            }

            // Append assistant message verbatim (must include the tool_use blocks).
            messages.append(["role": "assistant", "content": response.content])

            // Run each tool_use block and collect tool_result blocks.
            var toolResults: [[String: Any]] = []
            for block in response.content {
                guard let type = block["type"] as? String, type == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String else { continue }
                let input = (block["input"] as? [String: Any]) ?? [:]

                // Surface to UI before executing.
                if let onActivity {
                    let inputJSON = (try? String(data: JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted]), encoding: .utf8)) ?? "{}"
                    let activity = "\(name)(\(inputJSON))"
                    await MainActor.run { onActivity(activity) }
                }

                let resultText: String
                let isError: Bool
                if let tool = tools.first(where: { $0.name == name }) {
                    do {
                        resultText = try await tool.handler(input)
                        isError = false
                    } catch {
                        resultText = "Tool error: \(error.localizedDescription)"
                        isError = true
                    }
                } else {
                    resultText = "Unknown tool: \(name)"
                    isError = true
                }

                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": resultText,
                    "is_error": isError
                ])
            }
            messages.append(["role": "user", "content": toolResults])
        }
        // Clear activity once we're returning the final answer.
        if let onActivity {
            await MainActor.run { onActivity(nil) }
        }
        return collectedText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Single API call

    private struct CallResponse {
        let content: [[String: Any]]
        let stopReason: String?
    }

    private static func call(apiKey: String,
                             system: String,
                             tools: [AnthropicTool],
                             messages: [[String: Any]]) async throws -> CallResponse {
        var body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "system": system,
            "messages": messages
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema
                ] as [String: Any]
            }
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AnthropicError.requestFailed("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "?"
            throw AnthropicError.httpError(http.statusCode, msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AnthropicError.decodeFailed
        }
        return CallResponse(content: content, stopReason: json["stop_reason"] as? String)
    }
}
