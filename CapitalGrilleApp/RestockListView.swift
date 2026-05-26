import SwiftUI

struct RestockListView: View {
    @ObservedObject var restockStore: RestockStore
    @ObservedObject var wineStore: WineStore
    @State private var confirmClear = false

    var body: some View {
        Group {
            if restockStore.items.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundColor(.cgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(restockStore.items) { item in
                            RestockRow(item: item, wineStore: wineStore) {
                                Task { try? await restockStore.remove(item.product_id) }
                            }
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 76)
                        }

                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Text("Clear all")
                                .font(.callout)
                                .foregroundColor(.red)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .background(Color.cgBackground)
        .task { await restockStore.refresh() }
        .confirmationDialog("Clear the entire list?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Clear all", role: .destructive) {
                Task { try? await restockStore.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct RestockRow: View {
    let item: RestockItem
    @ObservedObject var wineStore: WineStore
    let onRemove: () -> Void

    private var wine: Wine? {
        wineStore.categories.flatMap(\.wines).first { $0.id == item.product_id }
    }

    private var backupLocation: WineLocation? {
        wineStore.locations[item.product_id]?.backup
    }

    var body: some View {
        HStack(spacing: 12) {
            if let wine {
                WineThumbnail(imageName: wine.image, size: 56)
            } else {
                Rectangle().fill(Color.cgBorder.opacity(0.4))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(wine?.name ?? item.product_id)
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.cgText)
                    .lineLimit(2)
                Text(backupLocation?.displayString ?? "—")
                    .font(.footnote)
                    .foregroundColor(.cgTextMuted)
            }
            Spacer()
            Text("×\(item.quantity)")
                .font(.system(.title3, design: .serif))
                .foregroundColor(.cgAccent)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.cgTextMuted.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}
