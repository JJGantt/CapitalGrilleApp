import Foundation

/// One item a guest ordered (`cg_orders`, data-layer 00125/00126). Written as heard, then renamed to its
/// menu name by the second pass; `standardized_at` is nil until that pass has looked at it.
struct Order: Codable, Identifiable, Hashable {
    let id: String
    let created_at: String
    let kind: String
    let item_id: String?
    let name: String
    let qty: Int
    let note: String?
    let heard_name: String?
    let standardized_at: String?

    var standardized: Bool { standardized_at != nil }
}

/// The open orders, newest first. The list lives behind the hub's owner-gated `/api/cg/orders` (status-hub
/// `server.js`), never the app's anon Supabase key: the app ships to testers, and that key would hand
/// every one of them the same list. Each write answers with the list as it now stands.
@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [Order] = []
    @Published private(set) var loaded = false
    @Published var loadError: String?
    /// Which model runs each pass: hub settings `cg_orders_model_first` / `cg_orders_model_second`, read
    /// with the list, so switching a model needs no build.
    private(set) var firstModel = "claude-sonnet-5"
    private(set) var secondModel = "claude-sonnet-5"

    private static let base = "https://jared-status-hub.fly.dev/api/cg/orders"

    func refresh() async {
        do { take(try await call("", method: "GET")) } catch { note(error) }
    }

    /// The first pass's items, as heard. Returns the rows as saved, for the second pass to rename.
    func add(_ items: [[String: Any]], heard: String, interactionId: UUID) async throws -> [Order] {
        let data = try await call("", method: "POST",
                                  body: ["items": items, "heard": heard, "interaction_id": interactionId.uuidString])
        take(data)
        struct Body: Decodable { let added: [Order] }
        return (try? JSONDecoder().decode(Body.self, from: data).added) ?? []
    }

    /// The second pass: each row matched to the menu, or marked as looked at and left as heard.
    func standardize(_ updates: [[String: Any]]) async throws {
        take(try await call("/standardize", method: "POST", body: ["updates": updates]))
    }

    func done(_ id: String) async {
        orders.removeAll { $0.id == id }
        do { take(try await call("/done", method: "POST", body: ["id": id])) } catch { recover(error) }
    }

    func clearAll() async {
        orders = []
        do { take(try await call("/done", method: "POST", body: ["all": true])) } catch { recover(error) }
    }

    private func take(_ data: Data) {
        struct Models: Decodable { let first: String; let second: String }
        struct Body: Decodable { let orders: [Order]; let models: Models? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return }
        orders = body.orders
        if let m = body.models { firstModel = m.first; secondModel = m.second }
        loaded = true
        loadError = nil
    }

    private func note(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        loadError = error.localizedDescription
    }

    /// A write that failed after the list was changed on screen: the list is read back once, so what
    /// shows is what is stored. A failed read is only noted; it does not read again.
    private func recover(_ error: Error) {
        note(error)
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

/// **Turns what was heard into orders, in two passes.**
///
/// 1. **As heard** (`write`): the transcript and the open orders go to the model, with no menu, and it
///    calls `add_orders` with each NEW item worded as it was said. They are on the list at once.
///    Deciding what is new happens here, because it decides what gets written: the bartender reads the
///    order back inside the recording, sometimes records a confirmation as a second one, and guests ask
///    about items they do not order, so the open orders go in with their age and the model adds only
///    what was ordered and is not already there. That judgement is the model's, not a matcher's.
/// 2. **Standardized** (`standardize`): those rows and the whole menu (every dish, cocktail, wine and
///    liquor with its id) go to the model, which calls `standardize` with a menu id for each row it can
///    place. The stored name is the menu's own, looked up from the id, never the model's spelling. A row
///    with no match, or an id not on the menu, keeps its heard wording: nothing is ever refused or lost,
///    and if this pass fails the heard rows are already on the list.
///
/// Each pass is one request (`finishAfterTools`): the tool call is the whole answer.
@MainActor
enum OrderTaker {
    /// The first pass. Returns the rows it wrote, as saved.
    static func write(_ heard: String, store: OrderStore, interactionId: UUID, sessionId: String) async throws -> [Order] {
        final class Box: @unchecked Sendable { var rows: [Order] = [] }
        let box = Box()
        let tool = AnthropicTool(
            name: "add_orders",
            description: "Add the new items to the order list, as heard. One call with every new item.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string", "description": "The item, as ordered."],
                                "qty": ["type": "integer", "minimum": 1],
                                "note": ["type": "string", "description": "How it was asked for. Omit if nothing."],
                            ],
                            "required": ["name", "qty"],
                        ],
                    ],
                ],
                "required": ["items"],
            ],
            handler: { input in
                let items: [[String: Any]] = ((input["items"] as? [[String: Any]]) ?? []).compactMap { i in
                    guard let name = (i["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
                    var item: [String: Any] = ["name": name, "qty": max(1, i["qty"] as? Int ?? 1)]
                    if let note = i["note"] as? String, !note.isEmpty { item["note"] = note }
                    return item
                }
                guard !items.isEmpty else { return "Nothing new." }
                box.rows = try await store.add(items, heard: heard, interactionId: interactionId)
                return "Added \(items.count)."
            }
        )
        _ = try await AnthropicClient.chatWithTools(
            question: heard, history: [], systemStable: firstRules, systemDynamic: recent(store.orders),
            tools: [tool], interactionId: interactionId, sessionId: sessionId,
            finishAfterTools: true, model: store.firstModel)
        return box.rows
    }

    /// The second pass, over the rows the first one wrote.
    static func standardize(_ rows: [Order], store: OrderStore, menu: MenuData?, bottles: [Bottle],
                            cocktails: [Cocktail], interactionId: UUID, sessionId: String) async throws {
        guard !rows.isEmpty else { return }
        let dishes = Dictionary((menu.map { $0.lunch + $0.dinner + $0.capital_hours } ?? []).map { ($0.name, $0) },
                                uniquingKeysWith: { a, _ in a })
        let drinks = Dictionary(cocktails.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let byId = Dictionary(bottles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rowIds = Set(rows.map(\.id))

        let tool = AnthropicTool(
            name: "standardize",
            description: "Match each order row to the menu. One call covering every row.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "rows": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "row": ["type": "string", "description": "The row's `row` value from ROWS, exactly; nothing else."],
                                "kind": ["type": "string", "enum": ["dish", "cocktail", "wine", "liquor"]],
                                "menu_id": ["type": "string", "description": "The menu item's id, exactly as listed. Omit when the row is not on the menu."],
                                "note": ["type": "string", "description": "The row's note, rewritten short. Omit to keep it."],
                            ],
                            "required": ["row"],
                        ],
                    ],
                ],
                "required": ["rows"],
            ],
            handler: { input in
                var updates: [String: [String: Any]] = [:]
                for r in (input["rows"] as? [[String: Any]]) ?? [] {
                    // The id is read out of whatever came back: a model asked for the row's id has been
                    // seen to return the whole row with it.
                    guard let said = r["row"] as? String,
                          let row = rowIds.first(where: { said.localizedCaseInsensitiveContains($0) }) else { continue }
                    var u: [String: Any] = ["id": row]
                    let id = r["menu_id"] as? String ?? ""
                    switch r["kind"] as? String {
                    case "dish": if let d = dishes[id] { u["kind"] = "dish"; u["item_id"] = d.name; u["name"] = d.name }
                    case "cocktail": if let c = drinks[id] { u["kind"] = "cocktail"; u["item_id"] = c.name; u["name"] = c.name }
                    case "wine", "liquor":
                        if let b = byId[id] { u["kind"] = b.kind == "wine" ? "wine" : "liquor"; u["item_id"] = b.id; u["name"] = b.displayName }
                    default: break
                    }
                    if u["item_id"] != nil, let note = r["note"] as? String { u["note"] = note.isEmpty ? NSNull() : note }
                    updates[row] = u
                }
                // A row the model left out is looked at all the same: it stays as heard.
                for row in rowIds where updates[row] == nil { updates[row] = ["id": row] }
                try await store.standardize(Array(updates.values))
                let matched = updates.values.filter { $0["item_id"] != nil }.count
                return "Matched \(matched) of \(rowIds.count)."
            }
        )
        let list = rows.map { o -> [String: Any] in
            var r: [String: Any] = ["row": o.id, "item": o.name, "qty": o.qty]
            if let note = o.note { r["note"] = note }
            return r
        }
        let listJSON = (try? String(data: JSONSerialization.data(withJSONObject: list), encoding: .utf8)) ?? "[]"
        _ = try await AnthropicClient.chatWithTools(
            question: "ROWS:\n" + listJSON, history: [],
            systemStable: secondRules + "\n\n" + catalog(dishes: Array(dishes.values), cocktails: Array(drinks.values), bottles: bottles),
            systemDynamic: "Every row is in the message.", tools: [tool], interactionId: interactionId, sessionId: sessionId,
            finishAfterTools: true, model: store.secondModel)
    }

    private static let firstRules = """
    You write down orders for a bartender at The Capital Grille. Each message is the speech-to-text of one recording made at the bar: a guest ordering, usually with the bartender reading the order back, sometimes with questions about the menu along the way. Call add_orders once with every NEW item. Do not reply with text: the call is the whole answer, and nothing you write is read.

    - Write each item the way it was ordered, cleaned of filler and spelled sensibly. Do not look anything up or rename it; a later pass matches items to the menu.
    - name is the item itself ("Tito's soda", "ribeye", "Old Fashioned"); note is only how it was asked for: temperature, neat/rocks/up, a mixer, a side, a swap, an allergy. Never repeat the name in the note.
    - Quantities: "two", "a couple", "for both of us" → qty. Default 1.
    - THE READ-BACK IS NOT A SECOND ORDER. The bartender repeats the order to confirm it; an item said by the guest and repeated back is ONE item. A correction ("actually make that a bottle", "no, rocks") changes the item it corrects rather than adding another.
    - A QUESTION IS NOT AN ORDER. "What's in the Old Fashioned?", "is the bisque good?", "what bourbons do you have?" add nothing, unless the guest then orders it.
    - The OPEN ORDERS below are already on the list. If this recording only confirms or repeats items already there from the last few minutes, add nothing for them. Add only what is new.
    - If nothing new was ordered (small talk, only questions, only a confirmation), call add_orders with no items.
    """

    private static let secondRules = """
    You match a bartender's order list at The Capital Grille to the menu. Each row in the message was written down as heard from speech-to-text. Call standardize once, with an entry for every row. Do not reply with text: the call is the whole answer.

    - A row that IS on the menu: its kind and menu id, exactly as listed below. Match by SOUND, because names arrive mangled by transcription ("whispering angle" is Whispering Angel, "stag" is Stagg). Every word counts: a word after a brand usually names which bottle of it (rye, reposado, 12 year).
    - A drink that is not one of our cocktails but is built on a bottle we carry is that bottle, with the build in the note: "Tito's soda" with "splash of cran" is the liquor Tito's, note "soda, splash cran".
    - A row NOT on the menu (a beer, a margarita, an off-menu request): give only its row id. It stays as written.
    - note: rewrite it short when the row is matched (only what changes the item, never the item's name); omit it to keep the row's note as is.
    - Never guess a menu item that does not fit. Leaving a row as written is always fine.
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
