import Foundation

// MARK: - Cocktail models

struct CocktailIngredient: Codable, Hashable {
    let name: String
    let amount: String?
}

struct Cocktail: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let glass: String?
    let garnish: String?
    let service: String?
    let ingredients: [CocktailIngredient]
    let prep: [String]
}

// MARK: - Loading

final class CocktailStore: ObservableObject {
    @Published var cocktails: [Cocktail] = []
    @Published var loadError: String?

    /// Loads the bundled cocktails immediately, then refreshes from Supabase so
    /// database edits go live without a rebuild. Bundled list stays as fallback.
    func load() {
        let list = CocktailStore.loadFromBundle()
        if list.isEmpty { loadError = "cocktails.json could not be decoded" }
        cocktails = list
        Task { await refreshFromRemote() }
    }

    @MainActor
    func refreshFromRemote() async {
        if let remote: [Cocktail] = try? await SupabaseClient.shared.get(
                path: "cocktails?select=*&order=sort.asc"), !remote.isEmpty {
            cocktails = remote
        }
    }

    /// Decodes the bundled cocktail list directly, without going through the
    /// `@Published` store — used to build the assistant's system prompt.
    static func loadFromBundle() -> [Cocktail] {
        guard let url = Bundle.main.url(forResource: "cocktails", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Cocktail].self, from: data) else { return [] }
        return list
    }
}

/// Compact one-block rendering of our cocktails for the assistant's system
/// prompt — name, glass/garnish/service, full build, and method per drink.
func cocktailSkeleton(_ cocktails: [Cocktail]) -> String {
    guard !cocktails.isEmpty else { return "" }
    var lines: [String] = []
    for (i, c) in cocktails.enumerated() {
        var head = "\(i + 1). \(c.name)"
        if let g = c.glass { head += " | Glass: \(g)" }
        if let garnish = c.garnish { head += " | Garnish: \(garnish)" }
        if let s = c.service { head += " | Service: \(s)" }
        lines.append(head)
        let build = c.ingredients.map { ing in
            ing.amount.map { "\(ing.name) \($0)" } ?? ing.name
        }.joined(separator: ", ")
        if !build.isEmpty { lines.append("   Build: \(build)") }
        if !c.prep.isEmpty { lines.append("   Method: \(c.prep.joined(separator: " "))") }
    }
    return lines.joined(separator: "\n")
}

func cocktailMatches(_ c: Cocktail, query q: String) -> Bool {
    if c.name.lowercased().contains(q) { return true }
    if let glass = c.glass?.lowercased(), glass.contains(q) { return true }
    if c.ingredients.contains(where: { $0.name.lowercased().contains(q) }) { return true }
    return false
}
