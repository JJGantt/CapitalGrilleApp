import SwiftUI

struct WatchRestockView: View {
    @StateObject private var store = RestockStore()
    @StateObject private var bottleStore = BottleStore()
    @State private var armedID: String?

    var body: some View {
        Group {
            if store.items.isEmpty && store.loadError == nil {
                Text("Restock list empty")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.loadError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                    .padding(8)
            } else {
                List {
                    Color.clear
                        .frame(height: 32)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    ForEach(store.items) { item in
                        rowButton(for: item)
                            .listRowBackground(
                                armedID == item.product_id
                                    ? Color.red.opacity(0.35)
                                    : Color.clear
                            )
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task {
            await bottleStore.refreshFromSupabase()
            await store.refresh()
        }
    }

    @ViewBuilder
    private func rowButton(for item: RestockItem) -> some View {
        Button(action: { handleTap(on: item) }) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(for: item))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    if let backup = backupLocation(for: item) {
                        Text(backup)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if armedID == item.product_id {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                } else {
                    Text("×\(item.quantity)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func handleTap(on item: RestockItem) {
        if armedID == item.product_id {
            // Confirmed — remove.
            let id = item.product_id
            armedID = nil
            Task {
                try? await store.remove(id)
            }
        } else {
            // Arm this row; auto-disarm after 3s if not confirmed.
            armedID = item.product_id
            let armed = item.product_id
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if armedID == armed { armedID = nil }
            }
        }
    }

    private func displayName(for item: RestockItem) -> String {
        if let b = bottleStore.bottles[item.product_id] { return b.displayName }
        if let n = item.name, !n.isEmpty { return n }
        return item.product_id
    }

    private func backupLocation(for item: RestockItem) -> String? {
        guard let b = bottleStore.bottles[item.product_id] else { return nil }
        return b.backup.displayString
    }
}
