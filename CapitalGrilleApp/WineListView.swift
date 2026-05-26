import SwiftUI

struct WineListView: View {
    @ObservedObject var store: WineStore
    let searchText: String
    let onTapWine: (Wine) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.categories.isEmpty {
                    if let err = store.loadError {
                        Text(err).foregroundColor(.red).padding()
                    } else {
                        ProgressView().padding(40)
                    }
                } else {
                    ForEach(filteredCategories()) { cat in
                        WineCategorySection(category: cat,
                                            locations: store.locations,
                                            onTapWine: onTapWine)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func filteredCategories() -> [WineCategory] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.categories }
        return store.categories.compactMap { cat in
            let matched = cat.wines.filter { w in
                w.name.lowercased().contains(q)
                || w.tasting_notes.lowercased().contains(q)
                || w.food_pairing.lowercased().contains(q)
            }
            return matched.isEmpty ? nil : WineCategory(name: cat.name, wines: matched)
        }
    }
}

private struct WineCategorySection: View {
    let category: WineCategory
    let locations: [String: WineRow]
    let onTapWine: (Wine) -> Void
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
                    ForEach(category.wines) { wine in
                        WineRowView(wine: wine,
                                    location: locations[wine.id]?.primary,
                                    onTap: { onTapWine(wine) })
                        if wine.id != category.wines.last?.id {
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
    let wine: Wine
    let location: WineLocation?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WineThumbnail(imageName: wine.image, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(wine.name)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let loc = location?.displayString {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.cgAccent.opacity(0.7))
                            Text(loc)
                                .font(.caption)
                                .foregroundColor(.cgTextMuted)
                        }
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
    let imageName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let img = loadWineImage(imageName) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Color.cgBorder.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
    }
}
