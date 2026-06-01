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
    @StateObject private var bottleStore = BottleStore()
    @StateObject private var restockStore = RestockStore()
    @StateObject private var voice = VoiceRecorder()
    @State private var searchText = ""
    @State private var section: TopSection = .food

    @State private var liquorExpanded: Set<String> = []
    @State private var selectedDish: Dish?
    @State private var selectedWine: Bottle?
    @State private var showSettings = false
    @State private var aiMode = true        // AI is the default field mode
    @State private var showAIResults = false  // chat overlay visibility
    @State private var aiInput = ""
    @State private var aiHistory: [QAExchange] = []
    @State private var aiSessionId: String = UUID().uuidString
    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var aiActivity: String?
    @State private var pendingQuestion: String?

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
                SettingsView(bottleStore: bottleStore)
            }
            .fullScreenCover(item: $selectedWine) { wine in
                NavigationStack {
                    WineDetailView(wine: wine, store: bottleStore)
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
                Task {
                    await bottleStore.refreshFromSupabase()
                    await restockStore.refresh()
                }
            }
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            // Top: Food / Wine / Liquor / Restock segmented control.
            // Tapping any segment also closes the AI conversation view — including
            // the currently-active segment (which native Picker wouldn't notify us about).
            HStack(spacing: 0) {
                ForEach(TopSection.allCases) { s in
                    Button(action: {
                        withAnimation {
                            section = s
                            if showAIResults { showAIResults = false }
                        }
                    }) {
                        Text(s.rawValue)
                            .font(.subheadline.weight(section == s ? .semibold : .regular))
                            .foregroundColor(section == s ? .cgText : .cgTextMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(section == s ? Color.cgCard : Color.clear)
                                    .padding(2)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.cgBorder.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: searchText) { _ in autoSwitchForSearch() }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)

            // Content first, takes remaining space; input bar pinned below it.
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            inputBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    var contentArea: some View {
        if showAIResults {
            aiResultsView
        } else if section == .wine {
            WineListView(store: bottleStore, searchText: searchText) { wine in
                selectedWine = wine
            }
        } else if section == .liquor {
            LiquorListView(bottleStore: bottleStore, expanded: $liquorExpanded) { bottle in
                selectedWine = bottle
            }
        } else if section == .restock {
            RestockListView(restockStore: restockStore, bottleStore: bottleStore)
        } else {
            menuListView
        }
    }

    var inputBar: some View {
        VStack(spacing: 6) {
        HStack(alignment: .top, spacing: 8) {
                if voice.isRecording {
                    HStack(alignment: .top, spacing: 8) {
                        PulsingMic()
                            .padding(.top, 2)
                        Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                            .font(.body)
                            .foregroundColor(.cgText)
                            .lineLimit(6, reservesSpace: false)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.green.opacity(0.7), lineWidth: 1.5))
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

                if voice.isRecording {
                    Button(action: { _ = voice.stop() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                    Button(action: primaryAIButtonTap) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                            .padding(8)
                    }
                } else {
                    // Mic always available — destination depends on current mode.
                    Button(action: { Task { await voice.start() } }) {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundColor(.cgAccent)
                            .padding(8)
                    }
                    // Toggle between AI and search modes.
                    Button(action: { withAnimation { aiMode.toggle() } }) {
                        Image(systemName: aiMode ? "magnifyingglass" : "sparkles")
                            .font(.title3)
                            .foregroundColor(aiMode ? .cgTextMuted : .cgAccent)
                            .padding(8)
                    }
                }
            }

            // Bottom toolbar: settings + chat-history toggle + clear (in chat with history)
            HStack {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.cgTextMuted)
                        .padding(8)
                }
                if !aiHistory.isEmpty {
                    Button(action: { withAnimation { showAIResults.toggle() } }) {
                        Image(systemName: showAIResults ? "bubble.left.fill" : "bubble.left")
                            .font(.title3)
                            .foregroundColor(showAIResults ? .cgAccent : .cgTextMuted)
                            .padding(8)
                    }
                }
                Spacer()
                if showAIResults && !aiHistory.isEmpty {
                    Button(action: { withAnimation {
                        aiHistory.removeAll()
                        aiError = nil
                        showAIResults = false
                        aiSessionId = UUID().uuidString
                    } }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                }
            }
        }
    }

    /// When the user types a search, jump to whichever tab has the most matches.
    /// Stays put if the current tab has the most (or if there are no matches anywhere).
    private func autoSwitchForSearch() {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        let foodCount: Int = {
            guard let menu = store.menu else { return 0 }
            return MenuGroup.allCases.reduce(0) { acc, g in
                acc + g.dishes(from: menu).filter { matches(dish: $0, query: q) }.count
            }
        }()
        let wineCount = bottleStore.wineCategories.flatMap(\.bottles).filter {
            $0.displayName.lowercased().contains(q)
            || ($0.tasting_notes ?? "").lowercased().contains(q)
            || ($0.food_pairing ?? "").lowercased().contains(q)
        }.count
        let liquorCount = bottleStore.liquors.filter {
            ($0.name ?? "").lowercased().contains(q)
        }.count

        let counts: [(TopSection, Int)] = [(.food, foodCount), (.wine, wineCount), (.liquor, liquorCount)]
        guard let best = counts.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return }

        // Stay put if current tab already has matches at the top.
        let currentCount = counts.first(where: { $0.0 == section })?.1 ?? 0
        if currentCount == best.1 { return }

        withAnimation { section = best.0 }
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

    /// Parse markdown so **bold**, *italic*, lists, etc. render properly.
    /// Falls back to plain text if parsing fails.
    private func renderMarkdown(_ source: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(source)
    }

    private func primaryAIButtonTap() {
        if voice.isRecording {
            let q = voice.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            if aiMode {
                askAI(question: q)
            } else {
                searchText = q
            }
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
        pendingQuestion = question
        withAnimation { showAIResults = true }

        Task {
            do {
                let answer = try await askAnything(question: question, history: history)
                await MainActor.run {
                    aiHistory.append(QAExchange(question: question, answer: answer))
                    pendingQuestion = nil
                    aiBusy = false
                    aiActivity = nil
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    pendingQuestion = nil
                    aiBusy = false
                    aiActivity = nil
                }
            }
        }
    }

    @MainActor
    private func askAnything(question: String, history: [(question: String, answer: String)]) async throws -> String {
        let engine = ChatEngine(menuStore: store, bottleStore: bottleStore, restockStore: restockStore, surface: "ios")
        return try await engine.ask(question: question, history: history, sessionId: aiSessionId) { activity in
            self.aiActivity = activity
        }
    }


    @ViewBuilder
    var aiResultsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                aiResultsContent
                Color.clear.frame(height: 1).id("bottomAnchor")
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            .onChange(of: aiHistory.count) { _ in
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
            .onChange(of: pendingQuestion) { _ in
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    var aiResultsContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                if aiHistory.isEmpty && aiError == nil && pendingQuestion == nil {
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
                            Text(renderMarkdown(ex.answer))
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
                if let pending = pendingQuestion {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(.cgTextMuted)
                                .font(.callout)
                            Text(pending)
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.cgText)
                        }
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.cgAccent)
                                .font(.callout)
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
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

    @ViewBuilder
    var menuListView: some View {
        ScrollView { menuListContent }
            .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    var menuListContent: some View {
        Group {
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
