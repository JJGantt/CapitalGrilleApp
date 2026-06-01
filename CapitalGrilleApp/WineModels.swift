import Foundation
import SwiftUI

// MARK: - Models

struct BottleLocation: Codable, Equatable {
    var area: String?
    var row: Int?
    var column: Int?

    var isEmpty: Bool { area == nil && row == nil && column == nil }

    var displayString: String? {
        guard let area else { return nil }
        var parts = [area]
        if let row { parts.append("Row \(row)") }
        if let column { parts.append("Col \(column)") }
        return parts.joined(separator: " · ")
    }
}

struct Bottle: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var kind: String?
    var category: String?
    var varietal: String?
    var tasting_notes: String?
    var food_pairing: String?
    var image_url: String?
    var price: Double?
    var bottle_price: Double?
    var deleted: Bool?
    var readonly: Bool?
    var primary_area: String?
    var primary_row: Int?
    var primary_column: Int?
    var backup_area: String?
    var backup_row: Int?
    var backup_column: Int?

    var displayName: String { name ?? id }
    var primary: BottleLocation { .init(area: primary_area, row: primary_row, column: primary_column) }
    var backup: BottleLocation { .init(area: backup_area, row: backup_row, column: backup_column) }
    var isDeleted: Bool { deleted == true }
    var isReadonly: Bool { readonly == true }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Bottle, rhs: Bottle) -> Bool { lhs.id == rhs.id }
}

struct BottleCategory: Identifiable {
    var id: String { name }
    let name: String
    let bottles: [Bottle]
}

struct BottleArea: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
}

// MARK: - Store

@MainActor
final class BottleStore: ObservableObject {
    @Published var bottles: [String: Bottle] = [:]
    @Published var areas: [BottleArea] = []
    @Published var loadError: String?

    private static let wineCategoryOrder = ["Sparkling & Rosé", "White Wine", "Red Wine"]

    /// Wines (kind == "wine") grouped by category, in canonical order. Each group sorted by name.
    var wineCategories: [BottleCategory] {
        let wines = bottles.values.filter { ($0.kind ?? "wine") == "wine" && !$0.isDeleted }
        let grouped = Dictionary(grouping: wines, by: { $0.category ?? "Other" })
        let sortKey: (Bottle, Bottle) -> Bool = { a, b in
            let av = a.varietal ?? "~"  // nulls sort last
            let bv = b.varietal ?? "~"
            if av != bv { return av < bv }
            return a.displayName < b.displayName
        }
        let known = Self.wineCategoryOrder.compactMap { name -> BottleCategory? in
            guard let entries = grouped[name], !entries.isEmpty else { return nil }
            return BottleCategory(name: name, bottles: entries.sorted(by: sortKey))
        }
        let unknownNames = grouped.keys.filter { !Self.wineCategoryOrder.contains($0) }.sorted()
        let unknown = unknownNames.map { name in
            BottleCategory(name: name, bottles: grouped[name]!.sorted(by: sortKey))
        }
        return known + unknown
    }

    var liquors: [Bottle] {
        bottles.values
            .filter { ($0.kind ?? "") == "liquor" && !$0.isDeleted }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Liquors grouped by varietal (Tequila, Bourbon, Vodka, etc.), alphabetical by varietal then name.
    var liquorCategories: [BottleCategory] {
        let onlyLiquors = bottles.values.filter { ($0.kind ?? "") == "liquor" && !$0.isDeleted }
        let grouped = Dictionary(grouping: onlyLiquors, by: { $0.varietal ?? "Other" })
        return grouped.keys.sorted().map { name in
            BottleCategory(name: name, bottles: grouped[name]!.sorted { $0.displayName < $1.displayName })
        }
    }

    func refreshFromSupabase() async {
        do {
            async let bottlesTask: [Bottle] = SupabaseClient.shared.get(path: "bottles?select=*&deleted=eq.false")
            async let areasTask: [BottleArea] = SupabaseClient.shared.get(path: "bottle_areas?select=*&order=name.asc")
            let (rows, areaList) = try await (bottlesTask, areasTask)
            self.bottles = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            self.areas = areaList
        } catch {
            self.loadError = "Supabase fetch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Mutations (Supabase)

    /// Apply a batch of location updates against EXISTING bottles only.
    /// Returns (updated ids, missing ids). Missing ids → caller should suggest add_product.
    func updateLocations(_ updates: [[String: Any]]) async throws -> (updated: [String], missing: [String]) {
        var updated: [String] = []
        var missing: [String] = []
        for u in updates {
            guard let bottleId = u["bottle_id"] as? String ?? u["wine_id"] as? String else { continue }

            var patch: [String: Any?] = [:]
            if let p = u["primary"] as? [String: Any] {
                if let v = p["area"]   as? String { patch["primary_area"]   = v }
                if let v = p["row"]    as? Int    { patch["primary_row"]    = v }
                if let v = p["column"] as? Int    { patch["primary_column"] = v }
            }
            if let b = u["backup"] as? [String: Any] {
                if let v = b["area"]   as? String { patch["backup_area"]   = v }
                if let v = b["row"]    as? Int    { patch["backup_row"]    = v }
                if let v = b["column"] as? Int    { patch["backup_column"] = v }
            }
            if patch.isEmpty { continue }

            let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(bottleId)", body: patch)
            if rows.isEmpty { missing.append(bottleId) } else { updated.append(bottleId) }
        }
        await refreshFromSupabase()
        return (updated, missing)
    }

    func addArea(_ name: String) async throws {
        try await SupabaseClient.shared.upsert(path: "bottle_areas",
            body: [["name": name]], onConflict: "name")
        await refreshFromSupabase()
    }

    func renameArea(_ name: String, to newName: String) async throws {
        try await SupabaseClient.shared.patch(path: "bottle_areas?name=eq.\(name)",
            body: ["name": newName])
        await refreshFromSupabase()
    }

    func removeArea(_ name: String) async throws {
        try await SupabaseClient.shared.delete(path: "bottle_areas?name=eq.\(name)")
        await refreshFromSupabase()
    }
}
