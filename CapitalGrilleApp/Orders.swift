import Foundation

/// One item a guest ordered, under its menu name (`cg_orders`, data-layer 00125).
struct Order: Codable, Identifiable, Hashable {
    let id: String
    let created_at: String
    let kind: String
    let item_id: String?
    let name: String
    let qty: Int
    let note: String?
}

/// The open orders, newest first. The list lives behind the hub's owner-gated `/api/cg/orders` (status-hub
/// `server.js`), never the app's anon Supabase key: the app ships to testers, and that key would hand
/// every one of them the same list. Each write answers with the list as it now stands.
@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [Order] = []
    @Published private(set) var loaded = false
    @Published var loadError: String?

    private static let base = "https://jared-status-hub.fly.dev/api/cg/orders"

    func refresh() async {
        do { take(try await call("", method: "GET")) } catch { fail(error) }
    }

    func add(_ items: [[String: Any]], heard: String, interactionId: UUID) async throws {
        take(try await call("", method: "POST",
                            body: ["items": items, "heard": heard, "interaction_id": interactionId.uuidString]))
    }

    func done(_ id: String) async {
        orders.removeAll { $0.id == id }
        do { take(try await call("/done", method: "POST", body: ["id": id])) } catch { fail(error) }
    }

    func clearAll() async {
        orders = []
        do { take(try await call("/done", method: "POST", body: ["all": true])) } catch { fail(error) }
    }

    private func take(_ data: Data) {
        struct Body: Decodable { let orders: [Order] }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return }
        orders = body.orders
        loaded = true
        loadError = nil
    }

    private func fail(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        loadError = error.localizedDescription
        Task { await refresh() }
    }

    private func call(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        guard let key = APIKeyStore.current else { throw AnthropicError.noAPIKey }
        var r = URLRequest(url: URL(string: Self.base + path)!)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "X-Owner-Key")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        r.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw AnthropicError.httpError(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }
}

/// Thrown by `add_orders` so the call counts as failed: the model gets one more turn to resend it, where a
/// successful call ends the exchange with no closing reply (`finishAfterTools`).
enum OrderError: LocalizedError {
    case unknownIds([String])
    var errorDescription: String? {
        switch self {
        case .unknownIds(let ids):
            return "Not added. These ids are not on the menu: \(ids.joined(separator: ", ")). Use ids exactly as listed, or kind other with the name as heard."
        }
    }
}

/// **Turns what was heard into orders on the menu.** The transcript goes to the model with the whole
/// menu — every dish, cocktail, wine and liquor with its id — and the model calls `add_orders` with the
/// ids. The name stored is the menu's own, taken from the id here, never the model's spelling, so the
/// same dish always reads the same on the list.
///
/// **Repeats are the model's call, not a matcher's**: the bartender reads the order back inside the same
/// recording, and sometimes records a confirmation as a second one, so the open orders go in with their
/// age and the model adds only what is new.
@MainActor
enum OrderTaker {
    static let tool = "add_orders"

    /// Returns how many items were added.
    static func take(_ heard: String, store: OrderStore, menu: MenuData?, bottles: [Bottle],
                     cocktails: [Cocktail], interactionId: UUID, sessionId: String) async throws -> Int {
        let dishes = Dictionary((menu.map { $0.lunch + $0.dinner + $0.capital_hours } ?? []).map { ($0.name, $0) },
                                uniquingKeysWith: { a, _ in a })
        let drinks = Dictionary(cocktails.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let byId = Dictionary(bottles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        final class Count: @unchecked Sendable { var n = 0 }
        let added = Count()
        let addOrders = AnthropicTool(
            name: tool,
            description: "Add the items the guest ordered to the order list. One call with every new item.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "kind": ["type": "string", "enum": ["dish", "cocktail", "wine", "liquor", "other"]],
                                "id": ["type": "string", "description": "The item's id from the menu below, exactly. Omit for kind other."],
                                "name": ["type": "string", "description": "Only for kind other: the item as heard."],
                                "qty": ["type": "integer", "minimum": 1],
                                "note": ["type": "string", "description": "How it was ordered: temperature, neat/rocks/up, a mixer, a side or a change. Omit if nothing."],
                            ],
                            "required": ["kind", "qty"],
                        ],
                    ],
                ],
                "required": ["items"],
            ],
            handler: { input in
                let raw = (input["items"] as? [[String: Any]]) ?? []
                var items: [[String: Any]] = []
                var unknown: [String] = []
                for i in raw {
                    let kind = i["kind"] as? String ?? "other"
                    let id = i["id"] as? String ?? ""
                    var item: [String: Any] = ["kind": kind, "qty": max(1, i["qty"] as? Int ?? 1)]
                    if let note = i["note"] as? String, !note.isEmpty { item["note"] = note }
                    switch kind {
                    case "dish":
                        guard let d = dishes[id] else { unknown.append(id); continue }
                        item["item_id"] = d.name; item["name"] = d.name
                    case "cocktail":
                        guard let c = drinks[id] else { unknown.append(id); continue }
                        item["item_id"] = c.name; item["name"] = c.name
                    case "wine", "liquor":
                        guard let b = byId[id] else { unknown.append(id); continue }
                        item["kind"] = b.kind == "wine" ? "wine" : "liquor"
                        item["item_id"] = b.id; item["name"] = b.displayName
                    default:
                        guard let name = i["name"] as? String, !name.isEmpty else { continue }
                        item["kind"] = "other"; item["name"] = name
                    }
                    items.append(item)
                }
                // Nothing is saved from a call with a bad id: the model resends the whole order with ids
                // from the list, rather than half of it landing.
                if !unknown.isEmpty {
                    throw OrderError.unknownIds(unknown)
                }
                guard !items.isEmpty else { return "Nothing to add." }
                try await store.add(items, heard: heard, interactionId: interactionId)
                added.n += items.count
                return "Added \(items.count)."
            }
        )

        _ = try await AnthropicClient.chatWithTools(
            question: heard,
            history: [],
            systemStable: rules + "\n\n" + catalog(dishes: Array(dishes.values), cocktails: Array(drinks.values), bottles: bottles),
            systemDynamic: recent(store.orders),
            tools: [addOrders],
            interactionId: interactionId,
            sessionId: sessionId,
            finishAfterTools: true
        )
        return added.n
    }

    private static let rules = """
    You take orders for a bartender at The Capital Grille. Each message is the speech-to-text of one recording made at the bar: a guest ordering, usually with the bartender reading the order back. Pull out what was ordered and call add_orders once with every NEW item. Do not reply with text: the call is the whole answer, and nothing you write is read.

    - Use the menu below. Every item names its id; pass the id exactly. Match by SOUND, because brand and dish names arrive mangled by transcription ("whispering angle" is Whispering Angel). Every word heard counts: "Tito's soda" is the liquor Tito's with the note "soda"; "a glass of the Caymus" is the wine Caymus with the note "glass".
    - A drink that is not one of our cocktails but is built on a bottle we carry is that bottle, with the build in the note: "Tito's and soda, splash of cran" is Tito's, note "soda, splash cran". A drink with no bottle named (a margarita, a beer, a soda) is kind other, named as heard.
    - A food item not on the menu is kind other, named as heard.
    - Quantities: "two", "a couple", "for both of us" → qty. Default 1.
    - Notes are short and only what changes the item: temperature (medium rare), neat/rocks/up, mixers, sides, swaps, allergies. Never repeat the item's name in its note.
    - THE READ-BACK IS NOT A SECOND ORDER. The bartender repeats the order to confirm it; an item said by the guest and repeated back is ONE item. A correction ("actually make that a Caymus", "no, rocks") changes the item it corrects rather than adding another.
    - The OPEN ORDERS below are already on the list. If this recording only confirms or repeats items already there from the last few minutes, add nothing for them. Add only what is new.
    - If nothing was ordered (small talk, a question), call nothing.
    """

    private static func catalog(dishes: [Dish], cocktails: [Cocktail], bottles: [Bottle]) -> String {
        var lines = ["MENU — each line is: name [id]"]
        lines.append("\nDISHES (kind dish):")
        for d in dishes.sorted(by: { $0.name < $1.name }) { lines.append("\(d.name) [\(d.name)]") }
        lines.append("\nCOCKTAILS (kind cocktail):")
        for c in cocktails.sorted(by: { $0.name < $1.name }) { lines.append("\(c.name) [\(c.name)]") }
        lines.append("\nWINES (kind wine):")
        for b in bottles.filter({ $0.kind == "wine" }).sorted(by: { $0.displayName < $1.displayName }) {
            lines.append("\(b.displayName) [\(b.id)]" + (b.varietal.map { " (\($0))" } ?? ""))
        }
        lines.append("\nLIQUORS (kind liquor):")
        for b in bottles.filter({ $0.kind != "wine" }).sorted(by: { $0.displayName < $1.displayName }) {
            lines.append("\(b.displayName) [\(b.id)]" + (b.varietal.map { " (\($0))" } ?? ""))
        }
        return lines.joined(separator: "\n")
    }

    private static func recent(_ orders: [Order]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        let lines = orders.prefix(30).map { o -> String in
            let at = iso.date(from: o.created_at) ?? now
            let mins = Int(now.timeIntervalSince(at) / 60)
            return "- \(o.qty)x \(o.name)" + (o.note.map { " (\($0))" } ?? "") + " — \(mins) min ago"
        }
        return "OPEN ORDERS, newest first:\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n"))
    }
}
