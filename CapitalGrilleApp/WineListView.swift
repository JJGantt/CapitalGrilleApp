import SwiftUI

struct WineListView: View {
    @ObservedObject var store: BottleStore
    let searchText: String
    let onTapWine: (Bottle) -> Void

    var body: some View {
        ScrollView {
            content
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if store.bottles.isEmpty {
                if let err = store.loadError {
                    Text(err).foregroundColor(.red).padding()
                } else {
                    ProgressView().padding(40)
                }
            } else {
                ForEach(filteredCategories()) { cat in
                    WineCategorySection(category: cat, onTapWine: onTapWine)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func filteredCategories() -> [BottleCategory] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.wineCategories }
        return store.wineCategories.compactMap { cat in
            let matched = cat.bottles.filter { w in
                w.displayName.lowercased().contains(q)
                || (w.tasting_notes ?? "").lowercased().contains(q)
                || (w.food_pairing ?? "").lowercased().contains(q)
            }
            return matched.isEmpty ? nil : BottleCategory(name: cat.name, bottles: matched)
        }
    }
}

private struct WineCategorySection: View {
    let category: BottleCategory
    let onTapWine: (Bottle) -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { expanded.toggle() } }) {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
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

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    ForEach(category.bottles) { wine in
                        WineRowView(wine: wine, onTap: { onTapWine(wine) })
                        if wine.id != category.bottles.last?.id {
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 70)
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

private struct WineRowView: View {
    let wine: Bottle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WineThumbnail(urlString: wine.image_url, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(wine.displayName)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(wine.primary.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                    if let s = wine.backup.displayString {
                        Text(s)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted.opacity(0.75))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgTextMuted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WineThumbnail: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        RemoteImage(urlString: urlString)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
    }
}
