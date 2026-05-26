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
                            RestockRow(item: item, wineStore: wineStore,
                                onChangeQty: { newQty in
                                    Task {
                                        try? await restockStore.apply([[
                                            "product_id": item.product_id,
                                            "product_kind": item.product_kind,
                                            "quantity": newQty
                                        ]])
                                    }
                                },
                                onRemove: {
                                    Task { try? await restockStore.remove(item.product_id) }
                                })
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
                .scrollDismissesKeyboard(.immediately)
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
    let onChangeQty: (Int) -> Void
    let onRemove: () -> Void

    private var wine: Wine? {
        wineStore.categories.flatMap(\.wines).first { $0.id == item.product_id }
    }
    private var primary: WineLocation? { wineStore.locations[item.product_id]?.primary }
    private var backup:  WineLocation? { wineStore.locations[item.product_id]?.backup  }

    var body: some View {
        HStack(spacing: 12) {
            if let wine {
                WineThumbnail(imageName: wine.image, size: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(wine?.name ?? item.name ?? item.product_id)
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.cgText)
                    .lineLimit(2)
                if wine != nil {
                    Text(primary?.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                    Text(backup?.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onChangeQty(item.quantity - 1) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.cgTextMuted)
                }
                .buttonStyle(.plain)

                Text("\(item.quantity)")
                    .font(.system(.title3, design: .serif))
                    .foregroundColor(.cgAccent)
                    .frame(minWidth: 22)

                Button(action: { onChangeQty(item.quantity + 1) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.cgAccent)
                }
                .buttonStyle(.plain)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundColor(.cgTextMuted.opacity(0.6))
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}
