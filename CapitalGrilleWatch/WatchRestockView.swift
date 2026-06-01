import SwiftUI

struct WatchRestockView: View {
    @StateObject private var store = RestockStore()

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
                List(store.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? item.product_id)
                                .font(.system(size: 13))
                            Text(item.product_kind)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("×\(item.quantity)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Restock")
        .task { await store.refresh() }
    }
}
