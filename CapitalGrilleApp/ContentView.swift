import SwiftUI

// MARK: - Pulsing mic indicator

struct PulsingMic: View {
    @State private var pulse = false
    var body: some View {
        Image(systemName: "mic.fill")
            .foregroundColor(.green)
            .scaleEffect(pulse ? 1.15 : 0.95)
            .opacity(pulse ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - Theme colors

extension Color {
    static let cgBackground = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let cgCard = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let cgText = Color(red: 0.16, green: 0.11, blue: 0.08)
    static let cgTextMuted = Color(red: 0.42, green: 0.34, blue: 0.29)
    static let cgAccent = Color(red: 0.45, green: 0.18, blue: 0.21)
    static let cgBorder = Color(red: 0.85, green: 0.80, blue: 0.72)
}

// MARK: - Content View

enum TopSection: String, CaseIterable, Identifiable {
    case food = "Food"
    case wine = "Wine"
    case liquor = "Liquor"
    case restock = "Restock"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var store = MenuStore()
    @StateObject private var wineStore = WineStore()
    @StateObject private var restockStore = RestockStore()
    @StateObject private var voice = VoiceRecorder()
    @State private var searchText = ""
    @State private var section: TopSection = .food

    @State private var selectedDish: Dish?
    @State private var selectedWine: Wine?
    @State private var showSettings = false
    @State private var aiMode = false
    @State private var aiInput = ""
    @State private var aiHistory: [QAExchange] = []
    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var aiActivity: String?

    struct QAExchange: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    var body: some View {
        mainContent
            .background(Color.cgBackground.ignoresSafeArea())
            .fullScreenCover(item: $selectedDish) { dish in
                NavigationStack {
                    DishDetailView(dish: dish)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedDish = nil }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("Back")
                                    }
                                    .foregroundColor(.cgAccent)
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(wineStore: wineStore)
            }
            .fullScreenCover(item: $selectedWine) { wine in
                NavigationStack {
                    WineDetailView(wine: wine, store: wineStore)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedWine = nil }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("Back")
                                    }
                                    .foregroundColor(.cgAccent)
                                }
                            }
                        }
                }
            }
            .onAppear {
                if store.menu == nil { store.load() }
                if wineStore.categories.isEmpty { wineStore.loadBundle() }
                Task {
                    await wineStore.refreshFromSupabase()
                    await restockStore.refresh()
                }
            }
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            // Top: Food / Wine segmented control
            Picker("Section", selection: $section) {
                ForEach(TopSection.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: section) { _ in
                if aiMode { withAnimation { aiMode = false } }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)

            // Top bar: search OR AI input OR live voice transcript, + ✨/mic button
            HStack(spacing: 8) {
                if voice.isRecording {
                    HStack(spacing: 8) {
                        PulsingMic()
                        Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                            .font(.body)
                            .foregroundColor(.cgText)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.green.opacity(0.7), lineWidth: 1.5))
                } else if aiMode || section != .restock {
                    HStack(spacing: 8) {
                        Image(systemName: aiMode ? "sparkles" : "magnifyingglass")
                            .foregroundColor(aiMode ? .cgAccent : .cgTextMuted)
                        if aiMode {
                            TextField("Ask the menu…", text: $aiInput)
                                .submitLabel(.send)
                                .onSubmit { askAI() }
                                .disabled(aiBusy)
                        } else {
                            TextField(section == .wine ? "Search wines…" : "Search dishes, ingredients…", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                        }
                        if aiMode {
                            if aiBusy {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                            } else {
                                Button(action: askAI) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(aiInput.trimmingCharacters(in: .whitespaces).isEmpty ? .cgBorder : .cgAccent)
                                }
                                .disabled(aiInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.cgTextMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(aiMode ? Color.cgAccent : Color.cgBorder, lineWidth: aiMode ? 1.5 : 1))
                } else {
                    Spacer()
                }

                Button(action: primaryAIButtonTap) {
                    Image(systemName: primaryAIButtonIcon)
                        .font(.title3)
                        .foregroundColor(voice.isRecording ? .green : .cgAccent)
                        .padding(8)
                }
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    if !voice.isRecording {
                        withAnimation { aiMode.toggle() }
                    }
                })

                if aiMode && !voice.isRecording {
                    Button(action: { withAnimation { aiMode = false } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if aiMode {
                aiResultsView
            } else if section == .wine {
                WineListView(store: wineStore, searchText: searchText) { wine in
                    selectedWine = wine
                }
            } else if section == .liquor {
                LiquorListView(wineStore: wineStore)
            } else if section == .restock {
                RestockListView(restockStore: restockStore, wineStore: wineStore)
            } else {
                menuListView
            }

            // Bottom toolbar: settings (left) + clear conversation (right, AI mode only)
            HStack {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.cgTextMuted)
                        .padding(10)
                }
                Spacer()
                if aiMode && !aiHistory.isEmpty {
                    Button(action: { withAnimation { aiHistory.removeAll(); aiError = nil } }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(10)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    func toggleAIMode() {
        withAnimation {
            aiMode.toggle()
            if !aiMode {
                aiInput = ""
                aiError = nil
            }
        }
    }

    private var primaryAIButtonIcon: String {
        if voice.isRecording { return "arrow.up.circle.fill" }
        return "sparkles"
    }

    private func primaryAIButtonTap() {
        if voice.isRecording {
            let q = voice.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            withAnimation { aiMode = true }
            askAI(question: q)
        } else {
            Task { await voice.start() }
        }
    }

    func askAI() {
        let q = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askAI(question: q)
    }

    func askAI(question: String) {
        guard !aiBusy else { return }
        let history = aiHistory.map { (question: $0.question, answer: $0.answer) }
        aiBusy = true
        aiError = nil
        aiActivity = nil
        aiInput = ""

        Task {
            do {
                let answer = try await askAnything(question: question, history: history)
                await MainActor.run {
                    aiHistory.append(QAExchange(question: question, answer: answer))
                    aiBusy = false
                    aiActivity = nil
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    aiBusy = false
                    aiActivity = nil
                }
            }
        }
    }

    @MainActor
    private func askAnything(question: String, history: [(question: String, answer: String)]) async throws -> String {
        // Always send food menu + wine list + areas. The model decides what's relevant.
        let menuJSON: String = {
            guard let menu = store.menu else { return "(menu unavailable)" }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            if let data = try? enc.encode(menu), let s = String(data: data, encoding: .utf8) { return s }
            return "(menu unavailable)"
        }()

        struct WineCtx: Encodable {
            let id: String
            let name: String
            let primary: WineLocation?
            let backup: WineLocation?
        }
        let wines: [WineCtx] = wineStore.categories.flatMap { cat in
            cat.wines.map { w in
                WineCtx(id: w.id, name: w.name,
                        primary: wineStore.locations[w.id]?.primary,
                        backup:  wineStore.locations[w.id]?.backup)
            }
        }
        let areas = wineStore.areas.map(\.name)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        let winesJSON = (try? String(data: enc.encode(wines), encoding: .utf8)) ?? "[]"
        let areasJSON = (try? String(data: JSONSerialization.data(withJSONObject: areas), encoding: .utf8)) ?? "[]"

        let toolName = Backend.current == .mac ? "mcp__wine__update_wine_locations" : "update_wine_locations"
        let areaTool = Backend.current == .mac ? "mcp__wine__edit_areas" : "edit_areas"
        let restockTool = Backend.current == .mac ? "mcp__wine__update_restock" : "update_restock"
        let addProductTool = Backend.current == .mac ? "mcp__wine__add_product" : "add_product"
        let deleteProductTool = Backend.current == .mac ? "mcp__wine__delete_product" : "delete_product"

        // Liquors snapshot from Supabase products (kind=liquor)
        let liquorsCtx = wineStore.liquors.map { row -> [String: Any] in
            var d: [String: Any] = ["id": row.id, "name": row.name ?? row.id]
            if let s = row.primary.displayString { d["primary"] = s }
            if let s = row.backup.displayString  { d["backup"]  = s }
            return d
        }
        let liquorsJSON = (try? String(data: JSONSerialization.data(withJSONObject: liquorsCtx), encoding: .utf8)) ?? "[]"

        // Current restock list snapshot
        let restockCtx = restockStore.items.map { item -> [String: Any] in
            ["product_id": item.product_id, "quantity": item.quantity]
        }
        let restockJSON = (try? String(data: JSONSerialization.data(withJSONObject: restockCtx), encoding: .utf8)) ?? "[]"
        let system = """
        You are a quick reference assistant for The Capital Grille bartender/server training. You answer questions about both food and wine, and can update wine bottle locations behind the bar.

        Be concise — 1-3 sentences unless a list is needed.

        FOOD MENU DATA:
        \(menuJSON)

        WINES (id, name, current primary/backup location):
        \(winesJSON)

        LIQUORS (id, name, locations) — empty until you start adding them:
        \(liquorsJSON)

        EXISTING WINE AREAS (use ONLY these names — never invent new ones):
        \(areasJSON)

        CURRENT RESTOCK LIST (product_id → quantity):
        \(restockJSON)

        Restock rules:
        - Quantity in update_restock is ABSOLUTE (the new total), not a delta. For relative phrasing like "take one off", compute the new value (current − 1) from the CURRENT RESTOCK LIST. Result ≤ 0 → quantity: 0 to remove.
        - For real products (wines today, liquors later), use the product's existing id from the WINES list and product_kind matching its kind. Omit the name field.
        - For items that don't match any real product (oranges, lemons, lime juice, ice, paper towels...), add as free-text: product_kind: "misc", product_id: a kebab-case slug of the name (e.g. "oranges", "lime-juice"), AND set the name field to the human-readable string ("Oranges", "Lime juice").
        - Match aggressively against real products when the user's phrasing plausibly refers to one. If it's clearly not in the product list, free-text. If it's ambiguous, ASK rather than guessing.
        - Batch multiple items in one call when the user lists them in sequence.

        Catalog rules:
        - To register a NEW bottle (wine or liquor) so it can be referenced later, call \(addProductTool) with id (kebab-case slug), name, kind, and any locations the user mentions.
        - Only call add_product when the user is explicitly cataloging a bottle. For one-off restock entries that don't need a catalog row, use \(restockTool) with product_kind 'misc' instead.
        - To remove a product call \(deleteProductTool). This is a soft delete — the data is preserved. Wines are readonly and cannot be deleted by you; if the user tries, explain and suggest they remove it manually in Supabase.

        Wine-location rules:
        - For lookups ("where is X?", "what's similar to Y?"), answer in plain text from the WINES data.
        - For setting locations ("Santa Margherita goes back 3", "I'm reading off back of bar top reds: A, B, C"), call \(toolName) with a batched updates array. When the user reads off a sequence, auto-increment column starting at 1.
        - Row enum: back/front for bar areas, top/bottom for coolers. Match the user's wording.
        - Fuzzy-match area names against the EXISTING WINE AREAS list. If no clear match, ask. Never call \(areaTool) to add an area unless the user explicitly asks for that.
        - After an update, briefly confirm what was set.
        """

        let updateTool = AnthropicTool(
            name: "update_wine_locations",
            description: "Set the primary or backup location for one or more wines. The 'area' must be one of the existing areas. 'row' must be back/front/top/bottom. 'column' is any integer (positive, zero, or negative — negatives are valid for bottles sitting to the left of the main row). When the user lists multiple wines in sequence on the same row, batch them all into one call with auto-incrementing columns.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "wine_id": ["type": "string", "description": "Wine ID from the WINES list"],
                                "primary": [
                                    "type": "object",
                                    "properties": [
                                        "area":   ["type": "string"],
                                        "row":    ["type": "string", "enum": ["back","front","top","bottom"]],
                                        "column": ["type": "integer"]
                                    ]
                                ],
                                "backup": [
                                    "type": "object",
                                    "properties": [
                                        "area":   ["type": "string"],
                                        "row":    ["type": "string", "enum": ["back","front","top","bottom"]],
                                        "column": ["type": "integer"]
                                    ]
                                ]
                            ],
                            "required": ["wine_id"]
                        ]
                    ]
                ],
                "required": ["updates"]
            ],
            handler: { input in
                let updates = (input["updates"] as? [[String: Any]]) ?? []
                let ids = try await wineStore.updateLocations(updates)
                return "Updated \(ids.count) wine(s): \(ids.joined(separator: ", "))"
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
                // Pre-check readonly to give a clean refusal message
                struct Row: Decodable { let readonly: Bool?; let name: String? }
                let existing: [Row] = (try? await SupabaseClient.shared.get(path: "wines?id=eq.\(pid)&select=readonly,name")) ?? []
                if existing.first?.readonly == true {
                    return "'\(existing.first?.name ?? pid)' is readonly and can't be deleted by the AI."
                }
                try await SupabaseClient.shared.patch(path: "wines?id=eq.\(pid)", body: ["deleted": true])
                await wineStore.refreshFromSupabase()
                return "Deleted '\(existing.first?.name ?? pid)'."
            }
        )

        let addProductDef = AnthropicTool(
            name: "add_product",
            description: "Create a new product in the catalog (wine, liquor, soda). Use when the user explicitly registers a new bottle. id is a kebab-case slug; location fields are all optional.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id":              ["type": "string"],
                    "name":            ["type": "string"],
                    "kind":            ["type": "string", "enum": ["wine","liquor","soda"]],
                    "primary_area":    ["type": "string"],
                    "primary_row":     ["type": "string", "enum": ["back","front","top","bottom"]],
                    "primary_column":  ["type": "integer"],
                    "backup_area":     ["type": "string"],
                    "backup_row":      ["type": "string", "enum": ["back","front","top","bottom"]],
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
                for k in ["primary_area","primary_row","primary_column","backup_area","backup_row","backup_column"] {
                    if let v = input[k] { row[k] = v }
                }
                try await SupabaseClient.shared.upsert(path: "wines", body: [row], onConflict: "id")
                await wineStore.refreshFromSupabase()
                return "Added \(row["kind"] ?? "?") '\(row["name"] ?? "?")'."
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
                    try await wineStore.addArea(name)
                    return "Added area '\(name)'."
                case "rename":
                    guard let newName = input["new_name"] as? String else { return "Missing new_name." }
                    try await wineStore.renameArea(name, to: newName)
                    return "Renamed '\(name)' to '\(newName)'."
                case "remove":
                    try await wineStore.removeArea(name)
                    return "Removed area '\(name)'."
                default:
                    return "Unknown action '\(action)'."
                }
            }
        )

        let activityHandler: @MainActor (String?) -> Void = { activity in
            self.aiActivity = activity
        }

        if Backend.current == .mac {
            let answer = try await MacClient.ask(
                question: question, history: history, systemPrompt: system, mode: "wine",
                onActivity: activityHandler
            )
            await wineStore.refreshFromSupabase()
            await restockStore.refresh()
            return answer
        }
        return try await AnthropicClient.chatWithTools(
            question: question,
            history: history,
            system: system,
            tools: [updateTool, areasTool, restockToolDef, addProductDef, deleteProductDef],
            onActivity: activityHandler
        )
    }

    @ViewBuilder
    var aiResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if aiHistory.isEmpty && aiError == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundColor(.cgAccent.opacity(0.5))
                        Text("Ask anything")
                            .font(.callout)
                            .foregroundColor(.cgTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
                if aiBusy, let activity = aiActivity {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundColor(.cgAccent.opacity(0.7))
                            .font(.caption)
                        Text(activity)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.cgTextMuted)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
                }
                ForEach(aiHistory) { ex in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(.cgTextMuted)
                                .font(.callout)
                            Text(ex.question)
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.cgText)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.cgAccent)
                                .font(.callout)
                            Text(ex.answer)
                                .font(.callout)
                                .foregroundColor(.cgText)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
                }
                if let err = aiError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    var menuListView: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let menu = store.menu {
                        ForEach(MenuGroup.allCases) { group in
                            let dishes = filteredDishes(group.dishes(from: menu))
                            if !dishes.isEmpty {
                                MenuGroupView(
                                    title: group.rawValue,
                                    dishes: dishes,
                                    sectionOrder: group.sectionOrder,
                                    defaultExpanded: group == .dinner || !searchText.isEmpty,
                                    forceExpandSections: !searchText.isEmpty,
                                    onTapDish: { dish in selectedDish = dish }
                                )
                                .id("\(group.rawValue)-\(searchText)")
                            }
                        }
                    } else if let err = store.loadError {
                        Text(err).foregroundColor(.red).padding()
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // Filter logic
    func filteredDishes(_ dishes: [Dish]) -> [Dish] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return dishes }
        return dishes.filter { matches(dish: $0, query: q) }
    }

    func matches(dish: Dish, query q: String) -> Bool {
        if dish.name.lowercased().contains(q) { return true }
        if let d = dish.description?.lowercased(), d.contains(q) { return true }
        if let mn = dish.menu_name?.lowercased(), mn.contains(q) { return true }
        if let sp = dish.serving_piece?.lowercased(), sp.contains(q) { return true }
        if let st = dish.station?.lowercased(), st.contains(q) { return true }
        if let portion = dish.portion {
            for p in portion {
                if let ing = p.ingredient?.lowercased(), ing.contains(q) { return true }
                if let am = p.amount?.lowercased(), am.contains(q) { return true }
                if let pr = p.prep?.lowercased(), pr.contains(q) { return true }
            }
        }
        if let garnish = dish.garnish {
            for g in garnish {
                if let ing = g.ingredient?.lowercased(), ing.contains(q) { return true }
            }
        }
        if let tp = dish.talking_points {
            for p in tp where p.lowercased().contains(q) { return true }
        }
        if let notes = dish.notes {
            for n in notes where n.lowercased().contains(q) { return true }
        }
        return false
    }
}

// MARK: - Menu Group (top-level: Dinner, Lunch, etc.)

struct MenuGroupView: View {
    let title: String
    let dishes: [Dish]
    let sectionOrder: [String]
    let defaultExpanded: Bool
    let forceExpandSections: Bool
    let onTapDish: (Dish) -> Void
    @State private var isExpanded: Bool

    init(title: String, dishes: [Dish], sectionOrder: [String], defaultExpanded: Bool, forceExpandSections: Bool, onTapDish: @escaping (Dish) -> Void) {
        self.title = title
        self.dishes = dishes
        self.sectionOrder = sectionOrder
        self.defaultExpanded = defaultExpanded
        self.forceExpandSections = forceExpandSections
        self.onTapDish = onTapDish
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        let sections = dishesBySection(dishes, sectionOrder: sectionOrder)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.cgAccent.opacity(0.7))
                    Text(title.uppercased())
                        .font(.system(.title3, design: .serif))
                        .tracking(3)
                        .foregroundColor(.cgAccent)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    if sections.count == 1 {
                        ForEach(sections[0].1) { dish in
                            DishRow(dish: dish, onTap: { onTapDish(dish) })
                            if dish.id != sections[0].1.last?.id {
                                Divider().background(Color.cgBorder.opacity(0.3))
                                    .padding(.leading, 70)
                            }
                        }
                    } else {
                        ForEach(sections, id: \.0) { section, items in
                            SectionView(title: section, dishes: items, defaultExpanded: forceExpandSections, onTapDish: onTapDish)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cgBorder, lineWidth: 1)
        )
    }
}

// MARK: - Section View

struct SectionView: View {
    let title: String
    let dishes: [Dish]
    let defaultExpanded: Bool
    let onTapDish: (Dish) -> Void
    @State private var isExpanded: Bool

    init(title: String, dishes: [Dish], defaultExpanded: Bool, onTapDish: @escaping (Dish) -> Void) {
        self.title = title
        self.dishes = dishes
        self.defaultExpanded = defaultExpanded
        self.onTapDish = onTapDish
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.cgTextMuted)
                    Text(title.uppercased())
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.semibold)
                        .tracking(1)
                        .foregroundColor(.cgText)
                    Text("(\(dishes.count))")
                        .font(.caption)
                        .foregroundColor(.cgTextMuted)
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(dishes) { dish in
                        DishRow(dish: dish, onTap: { onTapDish(dish) })
                        if dish.id != dishes.last?.id {
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 70)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            Divider().background(Color.cgBorder.opacity(0.4))
        }
    }
}

// MARK: - Dish Row

struct DishRow: View {
    let dish: Dish
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                DishThumbnail(imagePath: dish.image, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dish.name)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let price = dish.price {
                            Text("$\(price)")
                                .font(.caption.bold())
                                .foregroundColor(.cgAccent)
                        }
                        if let cal = dish.calories {
                            if dish.price != nil {
                                Text("·").foregroundColor(.cgTextMuted).font(.caption)
                            }
                            Text("\(cal) cal")
                                .font(.caption)
                                .foregroundColor(.cgTextMuted)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgTextMuted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dish Thumbnail

struct DishThumbnail: View {
    let imagePath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let path = imagePath, let image = loadImage(path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.cgBorder.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
    }
}

func loadImage(_ path: String) -> UIImage? {
    // path like "images/dishes/foo.jpg"
    let filename = (path as NSString).lastPathComponent
    let name = (filename as NSString).deletingPathExtension
    // Try various locations in the bundle
    let candidates = [
        Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/dishes"),
        Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "dishes"),
        Bundle.main.url(forResource: name, withExtension: "jpg")
    ]
    for url in candidates {
        if let url, let img = UIImage(contentsOfFile: url.path) {
            return img
        }
    }
    if let img = UIImage(named: name) { return img }
    return nil
}
