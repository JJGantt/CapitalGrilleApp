import Foundation
import SwiftUI
import UIKit

// MARK: - Bundled wine data (immutable: name, notes, pairing, image)

struct WineCategory: Codable, Identifiable {
    var id: String { name }
    let name: String
    let wines: [Wine]
}

struct Wine: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let tasting_notes: String
    let food_pairing: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Wine, rhs: Wine) -> Bool { lhs.id == rhs.id }
}

struct WinesData: Codable {
    let categories: [WineCategory]
}

// MARK: - Mutable location data (Supabase)

struct WineLocation: Codable, Equatable {
    var area: String?
    var row: String?     // "back" | "front" | "top" | "bottom"
    var column: Int?

    var isEmpty: Bool { area == nil && row == nil && column == nil }

    var displayString: String? {
        guard let area else { return nil }
        var parts = [area]
        if let row { parts.append(row) }
        if let column { parts.append("\(column)") }
        return parts.joined(separator: " · ")
    }
}

struct WineRow: Codable, Identifiable {
    let id: String
    var name: String?
    var kind: String?
    var primary_area: String?
    var primary_row: String?
    var primary_column: Int?
    var backup_area: String?
    var backup_row: String?
    var backup_column: Int?

    var primary: WineLocation { .init(area: primary_area, row: primary_row, column: primary_column) }
    var backup: WineLocation { .init(area: backup_area, row: backup_row, column: backup_column) }
}

struct WineArea: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
}

// MARK: - Store

@MainActor
final class WineStore: ObservableObject {
    @Published var categories: [WineCategory] = []
    @Published var locations: [String: WineRow] = [:]   // wine id → row
    @Published var areas: [WineArea] = []
    @Published var loadError: String?

    func loadBundle() {
        guard let url = Bundle.main.url(forResource: "wines", withExtension: "json") else {
            loadError = "wines.json not found in bundle"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            categories = try JSONDecoder().decode(WinesData.self, from: data).categories
        } catch {
            loadError = "Wine decode error: \(error)"
        }
    }

    func refreshFromSupabase() async {
        do {
            async let winesTask: [WineRow] = SupabaseClient.shared.get(path: "wines?select=*")
            async let areasTask: [WineArea] = SupabaseClient.shared.get(path: "wine_areas?select=*&order=name.asc")
            let (rows, areaList) = try await (winesTask, areasTask)
            self.locations = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            self.areas = areaList
        } catch {
            self.loadError = "Supabase fetch failed: \(error.localizedDescription)"
        }
    }

    func location(for wineId: String) -> WineLocation? {
        locations[wineId]?.primary
    }

    func backupLocation(for wineId: String) -> WineLocation? {
        locations[wineId]?.backup
    }

    /// All products with kind == "liquor", sorted by name.
    var liquors: [WineRow] {
        locations.values
            .filter { ($0.kind ?? "") == "liquor" }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    // MARK: - Mutations (Supabase)

    /// Apply a batch of location updates. Each entry may set primary, backup, or both.
    /// Pass `NSNull()` (or omit the key) to leave a field unchanged; pass explicit null in JSON
    /// from the model to clear a field. Returns the list of wine IDs that were updated.
    func updateLocations(_ updates: [[String: Any]]) async throws -> [String] {
        var updated: [String] = []
        for u in updates {
            guard let wineId = u["wine_id"] as? String else { continue }

            var patch: [String: Any?] = [:]
            if let p = u["primary"] as? [String: Any] {
                patch["primary_area"]   = p["area"] as? String
                patch["primary_row"]    = p["row"] as? String
                patch["primary_column"] = p["column"] as? Int
            }
            if let b = u["backup"] as? [String: Any] {
                patch["backup_area"]   = b["area"] as? String
                patch["backup_row"]    = b["row"] as? String
                patch["backup_column"] = b["column"] as? Int
            }
            if patch.isEmpty { continue }

            try await SupabaseClient.shared.patch(path: "wines?id=eq.\(wineId)", body: patch)
            updated.append(wineId)
        }
        // Refresh from server so local state reflects truth.
        await refreshFromSupabase()
        return updated
    }

    func addArea(_ name: String) async throws {
        try await SupabaseClient.shared.upsert(path: "wine_areas",
            body: [["name": name]], onConflict: "name")
        await refreshFromSupabase()
    }

    func renameArea(_ name: String, to newName: String) async throws {
        try await SupabaseClient.shared.patch(path: "wine_areas?name=eq.\(name)",
            body: ["name": newName])
        await refreshFromSupabase()
    }

    func removeArea(_ name: String) async throws {
        try await SupabaseClient.shared.delete(path: "wine_areas?name=eq.\(name)")
        await refreshFromSupabase()
    }
}

// MARK: - Wine image loader

func loadWineImage(_ name: String) -> UIImage? {
    for ext in ["jpg", "png", "jpeg"] {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "wine-bottles"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
    }
    return UIImage(named: name)
}
