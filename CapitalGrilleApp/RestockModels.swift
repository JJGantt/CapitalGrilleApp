import Foundation
import SwiftUI

struct RestockItem: Codable, Identifiable, Hashable {
    let product_id: String
    let product_kind: String
    let quantity: Int
    let added_at: String?

    var id: String { product_id }
}

@MainActor
final class RestockStore: ObservableObject {
    @Published var items: [RestockItem] = []
    @Published var loadError: String?

    func refresh() async {
        do {
            let rows: [RestockItem] = try await SupabaseClient.shared.get(path: "restock_items?select=*&order=added_at.asc")
            self.items = rows
        } catch {
            self.loadError = "Restock fetch failed: \(error.localizedDescription)"
        }
    }

    /// Upsert items; quantity == 0 deletes the row.
    func apply(_ updates: [[String: Any]]) async throws {
        for u in updates {
            guard let pid = u["product_id"] as? String,
                  let qty = u["quantity"] as? Int else { continue }
            if qty <= 0 {
                try await SupabaseClient.shared.delete(path: "restock_items?product_id=eq.\(pid)")
            } else {
                let kind = (u["product_kind"] as? String) ?? "wine"
                try await SupabaseClient.shared.upsert(
                    path: "restock_items",
                    body: [["product_id": pid, "product_kind": kind, "quantity": qty]],
                    onConflict: "product_id"
                )
            }
        }
        await refresh()
    }

    func remove(_ productId: String) async throws {
        try await SupabaseClient.shared.delete(path: "restock_items?product_id=eq.\(productId)")
        await refresh()
    }

    func clearAll() async throws {
        try await SupabaseClient.shared.delete(path: "restock_items?product_id=neq.__none__")
        await refresh()
    }
}
