import Foundation

/// Shared chat engine — builds the system prompt + tool definitions from the
/// app's stores and runs a single turn through either Mac (Claude Code) or
/// direct Anthropic API. Used by both the iOS app and the watch app so they
/// answer identically.
@MainActor
final class ChatEngine {
    private let menuStore: MenuStore
    private let bottleStore: BottleStore
    private let restockStore: RestockStore

    /// Surface name (e.g., "iOS", "Watch") prepended to logs.
    private let surface: String

    /// Extra context appended to the system prompt — used by the watch to
    /// remind the model the answer will be read on a small screen.
    private let surfaceHint: String?

    init(menuStore: MenuStore,
         bottleStore: BottleStore,
         restockStore: RestockStore,
         surface: String = "ios",
         surfaceHint: String? = nil) {
        self.menuStore = menuStore
        self.bottleStore = bottleStore
        self.restockStore = restockStore
        self.surface = surface
        self.surfaceHint = surfaceHint
    }

    func ask(question: String,
             history: [(question: String, answer: String)],
             sessionId: String,
             onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> String {
        let interactionId = UUID()
        let startedAt = Date()

        // Editable rule text comes from Supabase (app_content/system_prompt); on any
        // failure we fall back to the in-code literals, so the prompt never breaks.
        let remotePrompt = await Self.fetchPromptBlocks()
        let (systemStable, systemDynamic, tools) = buildPromptAndTools(remotePrompt: remotePrompt)
        let combinedSystem = systemStable + "\n\n" + systemDynamic

        func logInteraction(backend: String, answer: String?, error: String?) async {
            await AppLogger.shared.record(.init(
                timestamp: startedAt, interactionId: interactionId, sessionId: sessionId,
                backend: "\(surface):\(backend)", kind: "interaction", toolName: nil, input: nil,
                output: nil, error: error,
                latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                tokensIn: nil, tokensOut: nil,
                userInput: question, finalAnswer: answer))
            await AppLogger.shared.flush(interactionId)
        }

        if Backend.current == .mac {
            do {
                let answer = try await MacClient.ask(
                    question: question, history: history, systemPrompt: combinedSystem, mode: surface,
                    sessionId: sessionId,
                    onActivity: onActivity
                )
                await bottleStore.refreshFromSupabase()
                await restockStore.refresh()
                await logInteraction(backend: "mac", answer: answer, error: nil)
                return answer
            } catch {
                if Self.isConnectionError(error) {
                    if let onActivity { await MainActor.run { onActivity("Mac unreachable — falling back to API") } }
                    await AppLogger.shared.record(.init(
                        timestamp: Date(), interactionId: interactionId, sessionId: sessionId,
                        backend: "\(surface):mac", kind: "fallback", toolName: nil, input: nil,
                        output: nil, error: error.localizedDescription,
                        latencyMs: nil, tokensIn: nil, tokensOut: nil,
                        userInput: nil, finalAnswer: nil))
                    // fall through to Direct API
                } else {
                    await logInteraction(backend: "mac", answer: nil, error: error.localizedDescription)
                    throw error
                }
            }
        }

        do {
            let answer = try await AnthropicClient.chatWithTools(
                question: question,
                history: history,
                systemStable: systemStable,
                systemDynamic: systemDynamic,
                tools: tools,
                interactionId: interactionId,
                sessionId: sessionId,
                onActivity: onActivity
            )
            await bottleStore.refreshFromSupabase()
            await restockStore.refresh()
            await logInteraction(backend: "api", answer: answer, error: nil)
            return answer
        } catch {
            await logInteraction(backend: "api", answer: nil, error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Prompt + tools

    /// Fetch the editable rule blocks from Supabase (app_content/system_prompt).
    /// Returns nil on any failure → callers fall back to the in-code literals.
    static func fetchPromptBlocks() async -> [String: String]? {
        struct Row: Decodable { let data: [String: String] }
        if let rows: [Row] = try? await SupabaseClient.shared.get(
                path: "app_content?key=eq.system_prompt&select=data") {
            return rows.first?.data
        }
        return nil
    }

    private func buildPromptAndTools(remotePrompt: [String: String]?) -> (stable: String, dynamic: String, tools: [AnthropicTool]) {
        // Catalog skeleton
        func locStr(_ l: BottleLocation) -> String? {
            guard let area = l.area else { return nil }
            var parts = [area]
            if let r = l.row    { parts.append("R\(r)") }
            if let c = l.column { parts.append("C\(c)") }
            return parts.joined(separator: " ")
        }
        func formatBottle(_ b: Bottle) -> String {
            var s = "\(b.displayName) [id:\(b.id)]"
            let primary = locStr(b.primary)
            let backup  = locStr(b.backup)
            if let p = primary, let bk = backup { s += " @ \(p) | bk \(bk)" }
            else if let p = primary             { s += " @ \(p)" }
            else if let bk = backup             { s += " | bk \(bk)" }
            return s
        }
        var skeletonLines: [String] = ["WINES:"]
        for cat in bottleStore.wineCategories {
            let byVar = Dictionary(grouping: cat.bottles, by: { $0.varietal ?? "?" })
            for varietal in byVar.keys.sorted() {
                skeletonLines.append("[\(cat.name) · \(varietal)]")
                for b in byVar[varietal]!.sorted(by: { $0.displayName < $1.displayName }) {
                    skeletonLines.append("  \(formatBottle(b))")
                }
            }
        }
        skeletonLines.append("\nLIQUORS:")
        let byVarLiq = Dictionary(grouping: bottleStore.liquors, by: { $0.varietal ?? "?" })
        for varietal in byVarLiq.keys.sorted() {
            let bottles = byVarLiq[varietal]!.sorted(by: { $0.displayName < $1.displayName })
            skeletonLines.append("[\(varietal)] (\(bottles.count))")
            for b in bottles { skeletonLines.append("  \(formatBottle(b))") }
        }
        let bottleSkeleton = skeletonLines.joined(separator: "\n")

        let areas = bottleStore.areas.map(\.name)
        let areasJSON = (try? String(data: JSONSerialization.data(withJSONObject: areas), encoding: .utf8)) ?? "[]"

        let toolName = Backend.current == .mac ? "mcp__bottle__update_bottle_locations" : "update_bottle_locations"
        let areaTool = Backend.current == .mac ? "mcp__bottle__edit_areas" : "edit_areas"
        let restockTool = Backend.current == .mac ? "mcp__bottle__update_restock" : "update_restock"
        let addProductTool = Backend.current == .mac ? "mcp__bottle__add_product" : "add_product"
        let deleteProductTool = Backend.current == .mac ? "mcp__bottle__delete_product" : "delete_product"
        let detailsTool = Backend.current == .mac ? "mcp__bottle__get_bottle_details" : "get_bottle_details"
        let byVarietalTool = Backend.current == .mac ? "mcp__bottle__get_bottles_by_varietal" : "get_bottles_by_varietal"
        let foodTool = Backend.current == .mac ? "mcp__bottle__get_food_menu" : "get_food_menu"
        let generousPourTool = Backend.current == .mac ? "mcp__bottle__get_generous_pour" : "get_generous_pour"

        let restockCtx = restockStore.items.map { item -> [String: Any] in
            ["product_id": item.product_id, "quantity": item.quantity]
        }
        let restockJSON = (try? String(data: JSONSerialization.data(withJSONObject: restockCtx), encoding: .utf8)) ?? "[]"

        let cocktailsList = CocktailStore.loadFromBundle()
        let cocktailSkel = cocktailsList.isEmpty ? "" : cocktailSkeleton(cocktailsList)

        // Editable rule blocks live in Supabase (app_content/system_prompt). A remote
        // block (which uses {{placeholders}}) overrides the in-code literal; either
        // way, {{tool}}/{{data}} placeholders resolve to the live backend + data.
        let promptSub: [String: String] = [
            "{{food_tool}}": foodTool, "{{details_tool}}": detailsTool, "{{by_varietal_tool}}": byVarietalTool,
            "{{generous_pour_tool}}": generousPourTool, "{{location_tool}}": toolName, "{{area_tool}}": areaTool,
            "{{restock_tool}}": restockTool, "{{add_product_tool}}": addProductTool, "{{delete_product_tool}}": deleteProductTool,
            "{{bottle_skeleton}}": bottleSkeleton, "{{areas}}": areasJSON, "{{cocktail_skeleton}}": cocktailSkel, "{{restock}}": restockJSON,
        ]
        func promptBlock(_ key: String, _ fallback: String) -> String {
            guard let remote = remotePrompt?[key], !remote.isEmpty else { return fallback }
            var r = remote
            for (k, v) in promptSub { r = r.replacingOccurrences(of: k, with: v) }
            return r
        }

        let baseRulesFallback = """
        You are a quick reference assistant for The Capital Grille bartender/server training. You answer questions about food, wine, liquor, and the bar's inventory, and can update bottle locations behind the bar.

        Be concise — 1-3 sentences unless a list is needed.

        DATA POLICY — read carefully:
        - The catalog skeleton (bottle names + locations, grouped by varietal) is in your system prompt — use it for location questions ("where is X?") and to fuzzy-match voice transcriptions to bottle names.
        - EVERY bottle in the skeleton HAS full tasting notes available via the tools. If a bottle appears in the skeleton, its details exist. NEVER say a bottle is "not in the database", "not yet added", "details aren't fully loaded", "not fully loaded in the system", or any similar phrase implying missing data. If you want its details, call get_bottle_details with its id.
        - NEVER name, recommend, or reference a bottle that isn't in the catalog skeleton. When answering category or recommendation questions ("what's the smokiest scotch", "best Cabernet", "recommend a tequila"), only choose from bottles in the skeleton. If nothing in the catalog fits well, say so honestly ("we don't carry any heavily peated scotch — closest we have is Highland Park 18") — DO NOT reach for a famous example outside the catalog. We physically cannot serve what we don't stock.
        - For ANY substantive question about a bottle's flavor, history, production, additives, age, mash bill, etc., ALWAYS call get_bottle_details or get_bottles_by_varietal FIRST to fetch authoritative tasting notes. Your own knowledge is welcome to add color and context, but the tool data is the source of truth.
        - For questions about a category ("what are the smoky scotches", "which gins do you have"), ALWAYS call get_bottles_by_varietal to see every option with full notes — even if you think you know the answer.
        - A single producer's lineup can span multiple varietals. E.g. "Colonel E.H. Taylor" has bourbons AND a rye (Straight Rye, varietal "Rye"). "Angel's Envy" has a bourbon AND a rye (Angel's Envy Rye, varietal "Rye"). "WhistlePig" is all ryes. When asked about a brand or lineup, scan the WHOLE skeleton for every matching name across ALL varietal groups, then call get_bottle_details for each one. Don't assume a single varietal covers the whole lineup.
        - For ANY question about food/dishes, ALWAYS call get_food_menu (with a section if you can narrow it down). The menu data is the source of truth — never guess ingredients from your own knowledge.
        - GENEROUS POUR is a separate seasonal program (summer wine/tasting event). Its menu, wines, prices, dates, and recipes are NOT part of the regular food/wine catalog and live behind a dedicated tool, \(generousPourTool). ONLY call \(generousPourTool) when the user has explicitly mentioned "Generous Pour" (or a clear phonetic variant). Do not include Generous Pour wines or dishes in answers to ordinary food, wine, or recommendation questions. If the user mentions Generous Pour, \(generousPourTool) returns the full program data — wines, courses, recipes, and pricing — in one shot.
        - Tool calls are cheap — when in doubt, call the tool. Better to verify with data than guess.

        QUESTION-SHAPE RULES:
        - BARE NOUN PROMPTS: When the user's prompt is just the name of a thing (e.g. "White Russian", "Porcini Rub", "Old Fashioned", "Stagg") with no verb or question, treat it as a request for full information about that thing in the standard format for its type. Specifically:
          - Bare cocktail name (e.g. "Negroni", "White Russian") → same as "What's in a ___?" — apply COCKTAIL ROUTING (see OUR COCKTAILS below), then answer in the cocktail structure (Ingredients / Glass / Garnish / Instructions).
          - Bare food item (e.g. "Porcini Rub", "Kona Crust") → same as "What is X and what's in it?" — call get_food_menu, give a one-sentence description PLUS the ingredients list.
          - Bare bottle name (wine or liquor, e.g. "Orin Swift You Had Me at Hell No", "Stagg", "Macallan 18") → call get_bottle_details. LEAD WITH THE LOCATION: primary location on the first line, backup location on the second line if one exists. Then the tasting notes / production specs. The location is the most important fact for a bartender hearing a bottle name standalone — they need to know where to grab it before anything else.
          - Bare varietal/category (e.g. "Bourbon", "Cabernet") → same as "What X do we have?" — call get_bottles_by_varietal.
        - "What's in X?" / "What are the ingredients of X?" / "What's it made of?" / "How is X made?" → return the ACTUAL list of components/ingredients, one item per line, plain text. NEVER substitute a description for a list. THEN route by what X actually is:
          - X is a dish, sauce, rub, side, dessert, etc. → call get_food_menu and use its data as the source of truth. List the menu's exact ingredients verbatim, do not paraphrase or summarize.
          - X is a cocktail (Manhattan, Old Fashioned, Margarita, Negroni, White Russian, etc.) → apply COCKTAIL ROUTING (see OUR COCKTAILS below): prefer our version when X maps to one of ours, otherwise answer from general knowledge. No tool call needed — the recipes are in your prompt. Use this exact structure:
            Ingredients:
            <one per line with measurements>

            Glass:
            <glass type>

            Garnish:
            <garnish>

            Instructions:
            <method>

          - X is a single bottle (a specific wine or spirit) → call get_bottle_details.
        - For cocktail answers: if the standard recipe calls for a specific brand (e.g. "Patrón Silver"), only name the brand if it's in the catalog skeleton. Otherwise use the generic category ("blanco tequila", "coffee liqueur", "sweet vermouth").
        - "What dishes use X?" → list every dish whose menu entry mentions X.
        - "How is X different from Y?" / "Compare X and Y" → give the specific differences (proof, mash bill, finish, ingredients, etc.). Don't collapse to one vague difference.

        IMPORTANT — input comes from VOICE TRANSCRIPTION. Treat EVERYTHING phonetically before literally. The transcription will mishear words, drop punctuation, mis-capitalize, split or merge words, and substitute homophones. Your job is to recover intent from how the words SOUND, not how they're spelled.

        Apply this lens to every field:
        - **Numbers**: homophones map to digits — "for"/"four"/"fore" → 4; "to"/"two"/"too" → 2; "won"/"one" → 1; "ate"/"eight" → 8; "tree"/"three" → 3; "zero"/"oh" → 0; "negative one"/"minus one"/"neg one" → -1. Slots that expect a number ALWAYS take a number — never ask whether "for" meant 4.
        - **Sentences that appear cut off**: If a request appears to end abruptly with a word that sounds like a number ("...position for", "...column to", "...row one"), it is NOT truncated — that final word IS the number. Never respond with "your message seems cut off" or "could you clarify" for these. Treat "for"=4, "to"=2, "one"=1, "tree"=3, "ate"=8 even when they fall at the end of a sentence. The user's intent is always complete; trust your phonetic interpretation.
        - **Product names** (wines, liquors): fuzzy-match phonetically against the catalog — "rye on dough" → Riondo, "whispering angle" → Whispering Angel, "see do ree" → Siduri, "more raise day cass ah res" → Marqués de Cáceres, "Don who leo" → Don Julio. Match aggressively when one product is a clear phonetic fit. If TWO products are plausible matches and you genuinely can't tell, ask.
        - **Area names**: same phonetic match against the EXISTING WINE AREAS list — "bar top reds" might come through as "bartop reds" or "bar tops". Match to the closest existing area.
        - **Row numbers**: rows and columns are integers. "first"→1, "second"→2, "third"→3, etc. Apply the same homophone rules as other numbers.
        - **Action verbs**: "move", "set", "put", "place", "stick", "throw" all mean update location. "Add", "stock", "need" mean add to restock list. "Take off", "remove", "cross off", "got one" mean reduce restock quantity.

        Default behavior: trust your phonetic interpretation. Don't second-guess the user with clarifying questions unless multiple readings are genuinely equally plausible.
        """

        var systemStable = promptBlock("base_rules", baseRulesFallback)

        let cocktailRoutingFallback = cocktailsList.isEmpty ? "" : """
        OUR COCKTAILS — the cocktails on our bar menu, with full builds, are listed below.

        COCKTAIL ROUTING:
        - DEFAULT TO OURS. When asked about a cocktail, if it matches or plausibly maps to one on this list — including loose/partial matches (e.g. "Negroni" → our "Negroni Bianco", "Cosmo"/"Cosmopolitan" → "Capital Cosmopolitan", "Doli"/"Stoli Doli" → "The Doli", "Manhattan" → "Double Oaked & Rye Manhattan") — answer with OUR version and name it naturally ("Our Negroni Bianco is made with…").
        - Drop to general bartending knowledge ONLY when the drink clearly isn't one of ours (e.g. Irish Coffee, White Russian) OR the guest explicitly asks for the classic / standard / traditional version. Same answer structure either way.
        - NEVER say we "don't have" or "don't make" a cocktail. If it isn't on our list, just answer what it is from general knowledge.

        \(cocktailSkel)
        """
        let cocktailRouting = promptBlock("cocktail_routing", cocktailRoutingFallback)
        if !cocktailRouting.isEmpty { systemStable += "\n\n" + cocktailRouting }

        if let hint = surfaceHint {
            systemStable += "\n\nSURFACE NOTE: \(hint)"
        }

        let catalogRulesFallback = """
        CATALOG SKELETON (name @ primary location | bk backup location). Use for fuzzy matching and location lookups. For tasting notes / details, call \(detailsTool) or \(byVarietalTool).

        \(bottleSkeleton)

        EXISTING WINE AREAS (use ONLY these names — never invent new ones):
        \(areasJSON)

        Restock rules:
        - Quantity in update_restock is ABSOLUTE (the new total), not a delta. For relative phrasing like "take one off", compute the new value (current − 1) from the CURRENT RESTOCK LIST. Result ≤ 0 → quantity: 0 to remove.
        - For any product already in the catalog (wines OR liquors), use its existing id from the catalog skeleton and product_kind matching its kind. Omit the name field.
        - For items that don't match any real product (oranges, lemons, lime juice, ice, paper towels...), add as free-text: product_kind: "misc", product_id: a kebab-case slug of the name (e.g. "oranges", "lime-juice"), AND set the name field to the human-readable string ("Oranges", "Lime juice").
        - Match aggressively against real products when the user's phrasing plausibly refers to one. If it's clearly not in the product list, free-text. If it's ambiguous, ASK rather than guessing.
        - Batch multiple items in one call when the user lists them in sequence.

        Catalog rules:
        - To register a NEW bottle (wine or liquor) so it can be referenced later, call \(addProductTool) with id (kebab-case slug), name, kind, and any locations the user mentions.
        - Only call add_product when the user is explicitly cataloging a bottle. For one-off restock entries that don't need a catalog row, use \(restockTool) with product_kind 'misc' instead.
        - To remove a product call \(deleteProductTool). This is a soft delete — the data is preserved. Wines are readonly and cannot be deleted by you; if the user tries, explain and suggest they remove it manually in Supabase.

        Tool disambiguation (READ CAREFULLY — common mistake):
        - "Set/change/move/put the [primary|backup] location of X to ..." → \(toolName) (NEVER update_restock).
        - Any phrase mentioning "primary", "backup", "row", "column" with an area name → \(toolName).
        - "Add/I need X to the restock list", "two of these", "out of X" → \(restockTool).
        - If the user is RELOCATING a bottle (specifying where it sits), it's update_bottle_locations — quantity is irrelevant.
        - If the user is asking you to REMEMBER they need more of something, it's update_restock.
        - Questions about bottle CHARACTERISTICS (flavor, history, production, additives, age) → \(detailsTool) for one bottle or \(byVarietalTool) for a category.
        - Questions about FOOD → \(foodTool) (with section if you can narrow it).

        Bottle-location rules:
        - For lookups ("where is X?"), answer from the CATALOG SKELETON above.
        - For setting locations ("Santa Margherita goes back 3", "I'm reading off back of bar top reds: A, B, C"), call \(toolName) with a batched updates array. When the user reads off a sequence, auto-increment column starting at 1.
        - Rows and columns are integers (1, 2, 3…). "first row" → row 1, "second column" → column 2.
        - Fuzzy-match area names against the EXISTING WINE AREAS list. If no clear match, ask. Never call \(areaTool) to add an area unless the user explicitly asks for that.
        - After an update, briefly confirm what was set.
        """

        // The catalog skeleton + all the static rules are effectively static (the
        // skeleton changes only on a location edit), so fold them into the cached
        // prefix instead of re-billing them on every call. Only the live restock
        // list — which changes frequently — stays in the uncached block.
        systemStable += "\n\n" + promptBlock("catalog_rules", catalogRulesFallback)

        let systemDynamic = promptBlock("restock", """
        CURRENT RESTOCK LIST (product_id → quantity):
        \(restockJSON)
        """)

        // Tools — capture stores via closure
        let menuStore = self.menuStore
        let bottleStore = self.bottleStore
        let restockStore = self.restockStore

        let getFoodMenuTool = AnthropicTool(
            name: "get_food_menu",
            description: "Get The Capital Grille food menu. ALWAYS call this for food/dish questions. Use the 'section' parameter to narrow down — calling without a section returns just the list of section names + dish names (compact), which lets you pick the right section to drill into. Sections: lunch=['Appetizers & Soups','Entrée Salads','Sandwiches','Plates','Entrées'], dinner=['Appetizers','Soups & Salads','Chef Recommends','Hand-Carved Steaks & Chops','Enhancements','Seafood','Sides — For the Table','Desserts'], capital_hours=['Capital Hours']. NEVER call this for alcohol questions — use get_bottle_details or get_bottles_by_varietal instead.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "section": ["type": "string", "description": "Optional. Name of a section to drill into (returns full dish details for that section only). Omit to get a high-level list of sections + dish names."],
                    "meal": ["type": "string", "enum": ["lunch","dinner","capital_hours"], "description": "Optional. Restrict to a meal time."]
                ],
                "required": []
            ],
            handler: { input in
                guard let menu = await menuStore.menu else { return "(menu unavailable)" }
                let section = input["section"] as? String
                let meal = input["meal"] as? String

                func dishes(for m: String) -> [Dish] {
                    switch m {
                    case "lunch": return menu.lunch
                    case "dinner": return menu.dinner
                    case "capital_hours": return menu.capital_hours
                    default: return []
                    }
                }
                let mealList: [(String, [Dish])] = {
                    if let m = meal { return [(m, dishes(for: m))] }
                    return [("lunch", menu.lunch), ("dinner", menu.dinner), ("capital_hours", menu.capital_hours)]
                }()

                if section == nil {
                    var out: [String] = []
                    for (m, ds) in mealList {
                        out.append("=== \(m.uppercased()) (\(ds.count) dishes) ===")
                        let groups = Dictionary(grouping: ds, by: { $0.section })
                        for s in groups.keys.sorted() {
                            let names = groups[s]!.map { $0.name }
                            out.append("[\(s)] (\(names.count)): \(names.joined(separator: ", "))")
                        }
                        out.append("")
                    }
                    return out.joined(separator: "\n")
                }

                let targetSection = section!.lowercased()
                var matched: [Dish] = []
                for (_, ds) in mealList {
                    matched.append(contentsOf: ds.filter { $0.section.lowercased() == targetSection })
                }
                if matched.isEmpty { return "No dishes found in section '\(section!)'. Try calling without a section to see available section names." }
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted]
                if let data = try? enc.encode(matched), let s = String(data: data, encoding: .utf8) { return s }
                return "(encode error)"
            }
        )

        let getGenerousPourTool = AnthropicTool(
            name: "get_generous_pour",
            description: "Get the Generous Pour summer program data — wines, tasting menu courses, prices, dates, recipes. ONLY call this when the user explicitly mentions 'Generous Pour' (or an obvious phonetic variant like 'generous pore'). This is a seasonal event, NOT part of the regular menu. Never call this for general food, wine, or dish questions.",
            inputSchema: [
                "type": "object",
                "properties": [:],
                "required": []
            ],
            handler: { input in
                _ = input
                guard let gp = await menuStore.menu?.generous_pour else { return "(Generous Pour data unavailable)" }
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted]
                if let data = try? enc.encode(gp), let s = String(data: data, encoding: .utf8) { return s }
                return "(encode error)"
            }
        )

        let getBottleDetailsTool = AnthropicTool(
            name: "get_bottle_details",
            description: "Fetch full details (tasting notes, image URL, locations, category, varietal) for one bottle by id. ALWAYS call this when the user asks about a specific bottle's flavor, history, production, additives, age, or any substantive characteristic. Use the bottle id from the catalog skeleton.",
            inputSchema: [
                "type": "object",
                "properties": ["bottle_id": ["type": "string"]],
                "required": ["bottle_id"]
            ],
            handler: { input in
                let bid = (input["bottle_id"] as? String) ?? ""
                struct Row: Decodable {
                    let id: String; let name: String?; let kind: String?; let category: String?; let varietal: String?
                    let tasting_notes: String?; let food_pairing: String?; let image_url: String?
                    let primary_area: String?; let primary_row: Int?; let primary_column: Int?
                    let backup_area: String?; let backup_row: Int?; let backup_column: Int?
                }
                let rows: [Row] = (try? await SupabaseClient.shared.get(path: "bottles?id=eq.\(bid)&select=*")) ?? []
                guard let b = rows.first else { return "Bottle '\(bid)' not found." }
                var out = "\(b.name ?? b.id) [\(b.varietal ?? "?")]"
                if let c = b.category { out += " · \(c)" }
                if let p = b.primary_area {
                    var s = "\nPrimary: \(p)"
                    if let r = b.primary_row { s += " · R\(r)" }
                    if let c = b.primary_column { s += " · C\(c)" }
                    out += s
                }
                if let bk = b.backup_area {
                    var s = "\nBackup: \(bk)"
                    if let r = b.backup_row { s += " · R\(r)" }
                    if let c = b.backup_column { s += " · C\(c)" }
                    out += s
                }
                if let t = b.tasting_notes { out += "\n\nTasting notes: \(t)" }
                if let fp = b.food_pairing { out += "\n\nFood pairing: \(fp)" }
                if let u = b.image_url { out += "\n\nImage: \(u)" }
                return out
            }
        )

        let getBottlesByVarietalTool = AnthropicTool(
            name: "get_bottles_by_varietal",
            description: "Fetch ALL bottles of a given varietal with full tasting notes and locations. ALWAYS call this when the user asks about a category (e.g. 'what cabernets do you have', 'what are the smoky scotches', 'recommend a bourbon'). Returns the complete authoritative set — your knowledge is welcome to add color but the tool data is the source of truth.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "varietal": ["type": "string", "description": "Varietal name as it appears in the catalog skeleton (e.g. 'Cabernet Sauvignon', 'Bourbon', 'Scotch', 'Tequila', 'Champagne')."]
                ],
                "required": ["varietal"]
            ],
            handler: { input in
                let v = (input["varietal"] as? String) ?? ""
                struct Row: Decodable {
                    let id: String; let name: String?; let varietal: String?; let category: String?
                    let tasting_notes: String?
                    let primary_area: String?; let primary_row: Int?; let primary_column: Int?
                    let backup_area: String?; let backup_row: Int?; let backup_column: Int?
                }
                let escaped = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                let rows: [Row] = (try? await SupabaseClient.shared.get(path: "bottles?varietal=eq.\(escaped)&deleted=eq.false&select=id,name,varietal,category,tasting_notes,primary_area,primary_row,primary_column,backup_area,backup_row,backup_column&order=name.asc")) ?? []
                if rows.isEmpty { return "No bottles with varietal '\(v)' found." }
                var out: [String] = ["\(v.uppercased()) (\(rows.count) bottles):\n"]
                for b in rows {
                    var line = "• \(b.name ?? b.id)"
                    if let p = b.primary_area {
                        var s = " @ \(p)"
                        if let r = b.primary_row { s += " R\(r)" }
                        if let c = b.primary_column { s += " C\(c)" }
                        line += s
                    }
                    if let bk = b.backup_area {
                        var s = " | bk \(bk)"
                        if let r = b.backup_row { s += " R\(r)" }
                        if let c = b.backup_column { s += " C\(c)" }
                        line += s
                    }
                    out.append(line)
                    if let t = b.tasting_notes { out.append("  \(t)") }
                    out.append("")
                }
                return out.joined(separator: "\n")
            }
        )

        let updateTool = AnthropicTool(
            name: "update_bottle_locations",
            description: "Set the primary or backup location for one or more wines. The 'area' must be one of the existing areas. 'row' and 'column' are integers (positive, zero, or negative). When the user lists multiple wines in sequence on the same row, batch them all into one call with auto-incrementing columns.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "bottle_id": ["type": "string", "description": "Wine ID from the WINES list"],
                                "primary": [
                                    "type": "object",
                                    "properties": [
                                        "area":   ["type": "string"],
                                        "row":    ["type": "integer"],
                                        "column": ["type": "integer"]
                                    ]
                                ],
                                "backup": [
                                    "type": "object",
                                    "properties": [
                                        "area":   ["type": "string"],
                                        "row":    ["type": "integer"],
                                        "column": ["type": "integer"]
                                    ]
                                ]
                            ],
                            "required": ["bottle_id"]
                        ]
                    ]
                ],
                "required": ["updates"]
            ],
            handler: { input in
                let updates = (input["updates"] as? [[String: Any]]) ?? []
                let result = try await bottleStore.updateLocations(updates)
                var msg = "Updated \(result.updated.count) wine(s): \(result.updated.joined(separator: ", "))"
                if !result.missing.isEmpty {
                    msg += ". MISSING (these wines don't exist — call add_product first): \(result.missing.joined(separator: ", "))"
                }
                return msg
            }
        )

        let deleteProductDef = AnthropicTool(
            name: "delete_product",
            description: "Soft-delete a product from the catalog. Fails if the product is readonly. Data is preserved.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            handler: { input in
                let pid = (input["id"] as? String) ?? ""
                struct Row: Decodable { let readonly: Bool?; let name: String? }
                let existing: [Row] = (try? await SupabaseClient.shared.get(path: "bottles?id=eq.\(pid)&select=readonly,name")) ?? []
                if existing.first?.readonly == true {
                    return "'\(existing.first?.name ?? pid)' is readonly and can't be deleted by the AI."
                }
                try await SupabaseClient.shared.patch(path: "bottles?id=eq.\(pid)", body: ["deleted": true])
                await bottleStore.refreshFromSupabase()
                return "Deleted '\(existing.first?.name ?? pid)'."
            }
        )

        let addProductDef = AnthropicTool(
            name: "add_product",
            description: "Register a new product (wine, liquor, soda) in the catalog. Set name, kind, category, varietal, and optional location. DO NOT populate tasting_notes, food_pairing, or image_url here — those are filled in later via update_bottle_details and set_bottle_image. id is a kebab-case slug of the product name. For wines, category MUST be one of: 'Sparkling & Rosé', 'White Wine', 'Red Wine'; leave category empty for liquors. varietal is the marketing name on the bottle — for wines: 'Cabernet Sauvignon', 'Pinot Noir', 'Red Blend', 'Champagne', 'Prosecco', etc.; for liquors: 'Tequila', 'Bourbon', 'Vodka', 'Gin', 'Rum', 'Whiskey', 'Scotch', 'Cognac', 'Liqueur', etc. Use the bottle's own label.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id":              ["type": "string"],
                    "name":            ["type": "string"],
                    "kind":            ["type": "string", "enum": ["wine","liquor","soda"]],
                    "category":        ["type": "string", "enum": ["Sparkling & Rosé","White Wine","Red Wine"]],
                    "varietal":        ["type": "string"],
                    "primary_area":    ["type": "string"],
                    "primary_row":     ["type": "integer"],
                    "primary_column":  ["type": "integer"],
                    "backup_area":     ["type": "string"],
                    "backup_row":      ["type": "integer"],
                    "backup_column":   ["type": "integer"]
                ],
                "required": ["id","name","kind"]
            ],
            handler: { input in
                var row: [String: Any] = [
                    "id": (input["id"] as? String) ?? "",
                    "name": (input["name"] as? String) ?? "",
                    "kind": (input["kind"] as? String) ?? "wine"
                ]
                for k in ["category","varietal","primary_area","primary_row","primary_column","backup_area","backup_row","backup_column"] {
                    if let v = input[k] { row[k] = v }
                }
                try await SupabaseClient.shared.upsert(path: "bottles", body: [row], onConflict: "id")
                await bottleStore.refreshFromSupabase()
                return "Added \(row["kind"] ?? "?") '\(row["name"] ?? "?")'."
            }
        )

        let setImageDef = AnthropicTool(
            name: "set_bottle_image",
            description: "Set or replace a wine's bottle image URL. Prefer saratogawine.com product images (uniform white-background catalog shots like https://www.saratogawine.com/wp-content/uploads/.../xxx.jpg). If unavailable on Saratoga, fall back to the winery's own website. Always use a DIRECT image URL ending in .jpg/.png/.webp — never a product page URL.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "bottle_id":    ["type": "string"],
                    "image_url":  ["type": "string"]
                ],
                "required": ["bottle_id", "image_url"]
            ],
            handler: { input in
                let wid = (input["bottle_id"] as? String) ?? ""
                let url = (input["image_url"] as? String) ?? ""
                let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(wid)", body: ["image_url": url])
                await bottleStore.refreshFromSupabase()
                if rows.isEmpty { return "Wine '\(wid)' not found — call add_product first." }
                return "Set image for '\(wid)'."
            }
        )

        let updateDetailsDef = AnthropicTool(
            name: "update_bottle_details",
            description: "Edit a bottle's name, category, varietal, tasting notes, or food pairing. Only include fields you want to change. Use Capital Grille's voice for tasting notes and pairings — concise, professional, sensory-forward.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "bottle_id":     ["type": "string"],
                    "name":          ["type": "string"],
                    "category":      ["type": "string", "enum": ["Sparkling & Rosé","White Wine","Red Wine"]],
                    "varietal":      ["type": "string"],
                    "tasting_notes": ["type": "string"],
                    "food_pairing":  ["type": "string"]
                ],
                "required": ["bottle_id"]
            ],
            handler: { input in
                let wid = (input["bottle_id"] as? String) ?? ""
                var patch: [String: Any?] = [:]
                for k in ["name","category","varietal","tasting_notes","food_pairing"] {
                    if let v = input[k] as? String { patch[k] = v }
                }
                if patch.isEmpty { return "Nothing to update for '\(wid)'." }
                let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(wid)", body: patch)
                await bottleStore.refreshFromSupabase()
                if rows.isEmpty { return "Wine '\(wid)' not found." }
                return "Updated '\(wid)': \(patch.keys.sorted().joined(separator: ", "))."
            }
        )

        let restockToolDef = AnthropicTool(
            name: "update_restock",
            description: "Add/change/remove items on the restock list. quantity is ABSOLUTE (new total), quantity=0 removes. For real products use their existing id and matching kind. For free-text items (oranges, lemons, etc.) use product_kind 'misc', a slug id, AND a name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "product_id":   ["type": "string", "description": "Slug. Real product → its existing id; free-text → kebab-case of the name."],
                                "product_kind": ["type": "string", "enum": ["wine","liquor","soda","misc"]],
                                "quantity":     ["type": "integer", "minimum": 0],
                                "name":         ["type": "string", "description": "Display name. REQUIRED when product_kind is 'misc'."]
                            ],
                            "required": ["product_id", "quantity"]
                        ]
                    ]
                ],
                "required": ["updates"]
            ],
            handler: { input in
                let updates = (input["updates"] as? [[String: Any]]) ?? []
                try await restockStore.apply(updates)
                return "Updated restock list (\(updates.count) change(s))."
            }
        )

        let areasTool = AnthropicTool(
            name: "edit_areas",
            description: "Add, rename, or remove a wine storage area. Only call when the user explicitly asks to manage area names.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "action":   ["type": "string", "enum": ["add","rename","remove"]],
                    "name":     ["type": "string"],
                    "new_name": ["type": "string", "description": "Required for rename"]
                ],
                "required": ["action","name"]
            ],
            handler: { input in
                let action = (input["action"] as? String) ?? ""
                let name = (input["name"] as? String) ?? ""
                switch action {
                case "add":
                    try await bottleStore.addArea(name)
                    return "Added area '\(name)'."
                case "rename":
                    guard let newName = input["new_name"] as? String else { return "Missing new_name." }
                    try await bottleStore.renameArea(name, to: newName)
                    return "Renamed '\(name)' to '\(newName)'."
                case "remove":
                    try await bottleStore.removeArea(name)
                    return "Removed area '\(name)'."
                default:
                    return "Unknown action '\(action)'."
                }
            }
        )

        let tools: [AnthropicTool] = [
            getFoodMenuTool, getGenerousPourTool, getBottleDetailsTool, getBottlesByVarietalTool,
            updateTool, areasTool, restockToolDef,
            addProductDef, deleteProductDef, setImageDef, updateDetailsDef,
        ]
        return (systemStable, systemDynamic, tools)
    }

    private static func isConnectionError(_ error: Error) -> Bool {
        #if os(watchOS)
        // Watch-specific: phone relay unreachable means we should fall back to API.
        if case WatchPhoneRelay.RelayError.notReachable = error { return true }
        #endif
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorTimedOut,
             NSURLErrorNotConnectedToInternet:
            return true
        default:
            return false
        }
    }
}
