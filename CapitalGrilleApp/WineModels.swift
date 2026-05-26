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
