import Foundation

// MARK: - Top-level menu

struct MenuData: Codable {
    var lunch: [Dish] = []
    var dinner: [Dish] = []
    var capital_hours: [Dish] = []
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

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: Dish, rhs: Dish) -> Bool { lhs.name == rhs.name }

    enum CodingKeys: String, CodingKey {
        case name, section, page, price, calories, serves, menu_name, description,
             image, serving_piece, portion, garnish, to_bring, questions_to_ask,
             production_time, station, notes, talking_points, sizes, variants, tasting_notes
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
    }
}

// MARK: - Ingredient (used for portion and garnish entries)

struct Ingredient: Codable, Hashable {
    let ingredient: String?
    let amount: String?
    let prep: String?
}

// MARK: - Menu loading

final class MenuStore: ObservableObject {
    @Published var menu: MenuData?
    @Published var loadError: String?

    func load() {
        guard let url = Bundle.main.url(forResource: "food-menu", withExtension: "json") else {
            loadError = "food-menu.json not found in bundle"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            menu = try decoder.decode(MenuData.self, from: data)
        } catch {
            loadError = "Decode error: \(error)"
        }
    }
}

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
