import SwiftUI

struct LiquorListView: View {
    @ObservedObject var wineStore: WineStore

    var body: some View {
        Group {
            if wineStore.liquors.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundColor(.cgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(wineStore.liquors) { row in
                            LiquorRowView(row: row)
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .background(Color.cgBackground)
    }
}

private struct LiquorRowView: View {
    let row: WineRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name ?? row.id)
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.cgText)
                    .lineLimit(2)
                Text(row.primary.displayString ?? "—")
                    .font(.footnote)
                    .foregroundColor(.cgTextMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}
