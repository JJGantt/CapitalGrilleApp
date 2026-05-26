import SwiftUI

struct WineDetailView: View {
    let wine: Wine
    @ObservedObject var store: WineStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero bottle image
                ZStack {
                    Color.white
                    if let img = loadWineImage(wine.image) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 360)
                    }
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))

                Text(wine.name)
                    .font(.system(.title2, design: .serif))
                    .foregroundColor(.cgText)

                // Locations
                LocationCard(title: "Primary", location: store.locations[wine.id]?.primary)
                LocationCard(title: "Backup",  location: store.locations[wine.id]?.backup)

                // Tasting notes
                infoBlock(title: "Tasting Notes", body: wine.tasting_notes)
                infoBlock(title: "Food Pairing",  body: wine.food_pairing)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(Color.cgBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.bold())
                .tracking(2)
                .foregroundColor(.cgAccent)
            Text(body)
                .font(.system(.body, design: .serif))
                .foregroundColor(.cgText)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}

private struct LocationCard: View {
    let title: String
    let location: WineLocation?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundColor(.cgAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundColor(.cgTextMuted)
                if let s = location?.displayString {
                    Text(s)
                        .font(.system(.callout, design: .serif))
                        .foregroundColor(.cgText)
                } else {
                    Text("Not set")
                        .font(.system(.callout, design: .serif))
                        .foregroundColor(.cgTextMuted)
                        .italic()
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}
