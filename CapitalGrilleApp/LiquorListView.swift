import SwiftUI

struct LiquorListView: View {
    @ObservedObject var bottleStore: BottleStore
    @Binding var expanded: Set<String>
    let onTapBottle: (Bottle) -> Void

    var body: some View {
        Group {
            let cats = bottleStore.liquorCategories
            if cats.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundColor(.cgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(cats) { cat in
                            LiquorCategorySection(
                                category: cat,
                                isExpanded: expanded.contains(cat.name),
                                onToggle: {
                                    withAnimation {
                                        if expanded.contains(cat.name) {
                                            expanded.remove(cat.name)
                                        } else {
                                            expanded.insert(cat.name)
                                        }
                                    }
                                },
                                onTap: onTapBottle
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.cgBackground)
    }
}

private struct LiquorCategorySection: View {
    let category: BottleCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    let onTap: (Bottle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.cgAccent.opacity(0.7))
                    Text(category.name.uppercased())
                        .font(.system(.title3, design: .serif))
                        .tracking(3)
                        .foregroundColor(.cgAccent)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    ForEach(category.bottles) { row in
                        LiquorRowView(row: row, onTap: { onTap(row) })
                        if row.id != category.bottles.last?.id {
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}

private struct LiquorRowView: View {
    let row: Bottle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WineThumbnail(urlString: row.image_url, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.displayName)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .lineLimit(2)
                    Text(row.primary.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                    if let s = row.backup.displayString {
                        Text(s)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted.opacity(0.75))
                    }
                }
                Spacer()
                if let price = row.price {
                    Text("$\(price, specifier: price.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundColor(.cgAccent)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgTextMuted)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
