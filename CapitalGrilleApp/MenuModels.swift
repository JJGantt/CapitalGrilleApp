import Foundation

// MARK: - Top-level menu

struct MenuData: Codable {
    var lunch: [Dish] = []
    var dinner: [Dish] = []
    var capital_hours: [Dish] = []
    var generous_pour: GenerousPour?
}

// MARK: - Generous Pour (seasonal wine/tasting program)
//
// Standalone summer event (June 25 - Aug 30). Lives outside the normal
// lunch/dinner/capital_hours flow — the model is instructed NOT to surface this
// data unless the user mentions "Generous Pour" explicitly.

struct GenerousPour: Codable {
    let meta: GenerousPourMeta
    let wines: [GenerousPourWine]
    let courses: [GenerousPourCourse]
}

struct GenerousPourMeta: Codable {
    let dates_active: String
    let wine_only_price: Int
    let tasting_menu_price: Int
    let tasting_menu_includes_wine: Bool?
    let glass_pour_oz: Double?
    let glassware: GenerousPourGlassware?
    let notes: [String]?
}

struct GenerousPourGlassware: Codable {
    let item_number: String?
    let description: String?
    let case_pack: String?
}

struct GenerousPourWine: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let producer: String?
    let region: String?
    let varietal: String?
    let description: String?
    let tasting_notes: String?
    let suggested_pairing: String?
    let image_url: String?
}

struct GenerousPourCourse: Codable {
    let course: String
    let paired_wines: [String]
    let dishes: [Dish]
}

// MARK: - Dish

struct Dish: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let section: String
    let page: Int?
    let price: Int?
    let calories: Int?
    let serves: Int?
    let menu_name: String?
    let description: String?
    let image: String?
    let serving_piece: String?
    let portion: [Ingredient]?
    let garnish: [Ingredient]?
    let to_bring: [String]?
    let questions_to_ask: [String]?
    let production_time: String?
    let station: String?
    let notes: [String]?
    let talking_points: [String]?
    let sizes: [String: String]?
    let variants: [String: String]?
    let tasting_notes: String?
    let ingredients: DishIngredients?

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: Dish, rhs: Dish) -> Bool { lhs.name == rhs.name }

    init(name: String, section: String, page: Int? = nil, price: Int? = nil,
         calories: Int? = nil, serves: Int? = nil, menu_name: String? = nil,
         description: String? = nil, image: String? = nil, serving_piece: String? = nil,
         portion: [Ingredient]? = nil, garnish: [Ingredient]? = nil, to_bring: [String]? = nil,
         questions_to_ask: [String]? = nil, production_time: String? = nil, station: String? = nil,
         notes: [String]? = nil, talking_points: [String]? = nil, sizes: [String: String]? = nil,
         variants: [String: String]? = nil, tasting_notes: String? = nil, ingredients: DishIngredients? = nil) {
        self.name = name
        self.section = section
        self.page = page
        self.price = price
        self.calories = calories
        self.serves = serves
        self.menu_name = menu_name
        self.description = description
        self.image = image
        self.serving_piece = serving_piece
        self.portion = portion
        self.garnish = garnish
        self.to_bring = to_bring
        self.questions_to_ask = questions_to_ask
        self.production_time = production_time
        self.station = station
        self.notes = notes
        self.talking_points = talking_points
        self.sizes = sizes
        self.variants = variants
        self.tasting_notes = tasting_notes
        self.ingredients = ingredients
    }

    enum CodingKeys: String, CodingKey {
        case name, section, page, price, calories, serves, menu_name, description,
             image, serving_piece, portion, garnish, to_bring, questions_to_ask,
             production_time, station, notes, talking_points, sizes, variants, tasting_notes,
             ingredients
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        section = try c.decode(String.self, forKey: .section)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        price = try c.decodeIfPresent(Int.self, forKey: .price)
        calories = try c.decodeIfPresent(Int.self, forKey: .calories)
        serves = try c.decodeIfPresent(Int.self, forKey: .serves)
        menu_name = try c.decodeIfPresent(String.self, forKey: .menu_name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        serving_piece = try c.decodeIfPresent(String.self, forKey: .serving_piece)
        portion = try c.decodeIfPresent([Ingredient].self, forKey: .portion)
        // garnish can be array of Ingredient OR a single string
        if let arr = try? c.decode([Ingredient].self, forKey: .garnish) {
            garnish = arr
        } else if let str = try? c.decode(String.self, forKey: .garnish) {
            garnish = [Ingredient(ingredient: str, amount: nil, prep: nil)]
        } else {
            garnish = nil
        }
        to_bring = try c.decodeIfPresent([String].self, forKey: .to_bring)
        questions_to_ask = try c.decodeIfPresent([String].self, forKey: .questions_to_ask)
        production_time = try c.decodeIfPresent(String.self, forKey: .production_time)
        station = try c.decodeIfPresent(String.self, forKey: .station)
        notes = try c.decodeIfPresent([String].self, forKey: .notes)
        talking_points = try c.decodeIfPresent([String].self, forKey: .talking_points)
        sizes = try c.decodeIfPresent([String: String].self, forKey: .sizes)
        variants = try c.decodeIfPresent([String: String].self, forKey: .variants)
        tasting_notes = try c.decodeIfPresent(String.self, forKey: .tasting_notes)
        ingredients = try c.decodeIfPresent(DishIngredients.self, forKey: .ingredients)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(section, forKey: .section)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encodeIfPresent(price, forKey: .price)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(serves, forKey: .serves)
        try c.encodeIfPresent(menu_name, forKey: .menu_name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encodeIfPresent(serving_piece, forKey: .serving_piece)
        try c.encodeIfPresent(portion, forKey: .portion)
        try c.encodeIfPresent(garnish, forKey: .garnish)
        try c.encodeIfPresent(to_bring, forKey: .to_bring)
        try c.encodeIfPresent(questions_to_ask, forKey: .questions_to_ask)
        try c.encodeIfPresent(production_time, forKey: .production_time)
        try c.encodeIfPresent(station, forKey: .station)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(talking_points, forKey: .talking_points)
        try c.encodeIfPresent(sizes, forKey: .sizes)
        try c.encodeIfPresent(variants, forKey: .variants)
        try c.encodeIfPresent(tasting_notes, forKey: .tasting_notes)
        try c.encodeIfPresent(ingredients, forKey: .ingredients)
    }
}

// MARK: - Ingredient (used for portion and garnish entries)

struct Ingredient: Codable, Hashable {
    let ingredient: String?
    let amount: String?
    let prep: String?
}

// MARK: - DishIngredients (used by Enhancement entries — rubs/crusts/sauces)

struct DishIngredients: Codable, Hashable {
    let rub: [String]?
    let finishing: [String]?
    let crust: [String]?
    let components: [String]?
    let note: String?
}

// MARK: - Menu loading

final class MenuStore: ObservableObject {
    @Published var menu: MenuData?
    @Published var loadError: String?

    /// Loads the bundled menu immediately (instant, offline-safe), then refreshes
    /// from Supabase in the background so database edits go live without a rebuild.
    func load() {
        loadBundled()
        Task { await refreshFromRemote() }
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "food-menu", withExtension: "json") else {
            loadError = "food-menu.json not found in bundle"
            return
        }
        do {
            menu = try JSONDecoder().decode(MenuData.self, from: Data(contentsOf: url))
        } catch {
            loadError = "Decode error: \(error)"
        }
    }

    /// Fetch the menu from Supabase (per-dish rows + Generous Pour blob) and swap
    /// it in. On any failure or empty result, the bundled menu stays in place.
    @MainActor
    func refreshFromRemote() async {
        guard let remote = await Self.fetchRemote() else { return }
        menu = remote
    }

    private static func fetchRemote() async -> MenuData? {
        guard let rows: [MenuDishRow] = try? await SupabaseClient.shared.get(
                path: "menu_dishes?select=*&order=menu.asc,sort.asc"),
              !rows.isEmpty else { return nil }
        var data = MenuData()
        for r in rows {
            switch r.menu {
            case "lunch":         data.lunch.append(r.dish)
            case "dinner":        data.dinner.append(r.dish)
            case "capital_hours": data.capital_hours.append(r.dish)
            default: break
            }
        }
        if let gp: [GenerousPourRow] = try? await SupabaseClient.shared.get(
                path: "app_content?key=eq.generous_pour&select=data") {
            data.generous_pour = gp.first?.data
        }
        return data
    }
}

/// One `menu_dishes` row: the dish fields (decoded straight into `Dish`) plus the
/// menu group it belongs to. Extra columns (id, sort, updated_at) are ignored.
private struct MenuDishRow: Decodable {
    let menu: String
    let dish: Dish
    enum CodingKeys: String, CodingKey { case menu }
    init(from decoder: Decoder) throws {
        menu = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .menu)
        dish = try Dish(from: decoder)
    }
}

private struct GenerousPourRow: Decodable { let data: GenerousPour }

// MARK: - Section ordering helpers

enum MenuGroup: String, CaseIterable, Identifiable {
    case dinner = "Dinner"
    case lunch = "Lunch"
    case capitalHours = "Capital Hours"

    var id: String { rawValue }

    var sectionOrder: [String] {
        switch self {
        case .dinner: return [
            "Appetizers",
            "Soups & Salads",
            "Chef Recommends",
            "Hand-Carved Steaks & Chops",
            "Enhancements",
            "Seafood",
            "Sides — For the Table",
            "Desserts"
        ]
        case .lunch: return [
            "Appetizers & Soups",
            "Entrée Salads",
            "Sandwiches",
            "Plates",
            "Entrées"
        ]
        case .capitalHours: return ["Capital Hours"]
        }
    }

    func dishes(from menu: MenuData) -> [Dish] {
        switch self {
        case .dinner: return menu.dinner
        case .lunch: return menu.lunch
        case .capitalHours: return menu.capital_hours
        }
    }
}

// MARK: - Generous Pour search helpers

func gpWineMatches(_ w: GenerousPourWine, query q: String) -> Bool {
    let fields = [w.name, w.producer, w.region, w.varietal, w.description, w.tasting_notes, w.suggested_pairing]
    return fields.contains { ($0?.lowercased().contains(q)) == true }
}

func gpDishMatches(_ d: Dish, query q: String) -> Bool {
    if d.name.lowercased().contains(q) { return true }
    if let desc = d.description?.lowercased(), desc.contains(q) { return true }
    if let mn = d.menu_name?.lowercased(), mn.contains(q) { return true }
    return false
}

// MARK: - Generous Pour → full-recipe resolution
//
// Generous Pour course dishes are stubs (menu-line only). Many of them are the
// exact same dish that appears on the regular menu with full recipe details
// (portion, talking points, etc.). Resolve a stub to its full menu dish by an
// exact *normalized* name match so the detail view shows the real recipe. Only
// confident (normalized-equal) matches substitute — GP-specific platings that
// have no twin on the regular menu keep their stub.

func normalizeDishName(_ s: String) -> String {
    var t = s.lowercased()
    for prefix in ["seasonal:", "upgrade:"] where t.hasPrefix(prefix) {
        t = String(t.dropFirst(prefix.count))
    }
    t = t.replacingOccurrences(of: "&", with: "and")
    // Drop all punctuation, collapse whitespace.
    let words = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    return words.joined(separator: " ")
}

/// Builds a lookup of the regular menu (dinner + lunch + capital hours) keyed by
/// normalized dish name. First occurrence wins.
func fullMenuDishIndex(_ menu: MenuData) -> [String: Dish] {
    var index: [String: Dish] = [:]
    for dish in menu.dinner + menu.lunch + menu.capital_hours {
        let key = normalizeDishName(dish.name)
        if index[key] == nil { index[key] = dish }
    }
    return index
}

extension Dish {
    /// Fills in only the missing *qualitative* recipe details from a regular-menu
    /// twin. Every field the Generous Pour entry already specifies is kept exactly
    /// (GP spec trumps). Portion sizes, à-la-carte price, calories, and serving
    /// counts are intentionally NOT borrowed — those don't transfer to the GP
    /// tasting-menu plating. A stub's "recipe details to follow" placeholder note
    /// is dropped once the real details are filled in.
    func fillingRecipeDetails(from source: Dish) -> Dish {
        let gpRealNotes = (notes ?? []).filter { !$0.lowercased().contains("recipe details to follow") }
        let mergedNotes = gpRealNotes.isEmpty ? source.notes : gpRealNotes
        return Dish(
            name: name,
            section: section,
            page: page ?? source.page,
            price: price,                 // GP is prix-fixe — never borrow à-la-carte price
            calories: calories,           // portion-dependent — never borrow
            serves: serves,               // never borrow
            menu_name: menu_name ?? source.menu_name,
            description: description ?? source.description,
            image: image ?? source.image,
            serving_piece: serving_piece ?? source.serving_piece,
            portion: portion,             // portion sizes don't transfer — keep GP's own only
            garnish: garnish ?? source.garnish,
            to_bring: to_bring ?? source.to_bring,
            questions_to_ask: questions_to_ask ?? source.questions_to_ask,
            production_time: production_time ?? source.production_time,
            station: station ?? source.station,
            notes: mergedNotes,
            talking_points: talking_points ?? source.talking_points,
            sizes: sizes,                 // portion sizes don't transfer — keep GP's own only
            variants: variants ?? source.variants,
            tasting_notes: tasting_notes ?? source.tasting_notes,
            ingredients: ingredients ?? source.ingredients
        )
    }
}

/// Resolves a Generous Pour stub against the regular menu by exact normalized
/// name. On a confident match, the stub is enriched with the twin's recipe
/// details (GP spec always wins; portion/price specs are not borrowed).
/// No match → returned unchanged.
func resolveGenerousPourDish(_ dish: Dish, using index: [String: Dish]) -> Dish {
    if let full = index[normalizeDishName(dish.name)] { return dish.fillingRecipeDetails(from: full) }
    if let mn = dish.menu_name, let full = index[normalizeDishName(mn)] { return dish.fillingRecipeDetails(from: full) }
    return dish
}

func dishesBySection(_ dishes: [Dish], sectionOrder: [String]) -> [(String, [Dish])] {
    var grouped: [String: [Dish]] = [:]
    for d in dishes {
        grouped[d.section, default: []].append(d)
    }
    var result: [(String, [Dish])] = []
    for s in sectionOrder where grouped[s] != nil {
        result.append((s, grouped[s]!))
    }
    for s in grouped.keys where !sectionOrder.contains(s) {
        result.append((s, grouped[s]!))
    }
    return result
}
