import SwiftUI

struct WineDetailView: View {
    let wine: Bottle
    @ObservedObject var store: BottleStore

    /// Always read the freshest copy from the store so locations updated by the AI
    /// reflect immediately without re-presenting the view.
    private var current: Bottle { store.bottles[wine.id] ?? wine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Color.white
                    RemoteImage(urlString: current.image_url)
                        .frame(maxHeight: 360)
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))

                HStack(alignment: .firstTextBaseline) {
                    Text(current.displayName)
                        .font(.system(.title2, design: .serif))
                        .foregroundColor(.cgText)
                    Spacer()
                    if let price = current.price {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("$\(price, specifier: price.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                                .font(.system(.title3, design: .serif).weight(.semibold))
                                .foregroundColor(.cgAccent)
                            if let bottlePrice = current.bottle_price {
                                Text("$\(bottlePrice, specifier: bottlePrice.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f") btl")
                                    .font(.caption)
                                    .foregroundColor(.cgTextMuted)
                            }
                        }
                    }
                }

                LocationCard(title: "Primary", location: current.primary)
                LocationCard(title: "Backup",  location: current.backup)

                if let notes = current.tasting_notes, !notes.isEmpty {
                    infoBlock(title: "Tasting Notes", body: notes)
                }
                if let pairing = current.food_pairing, !pairing.isEmpty {
                    infoBlock(title: "Food Pairing", body: pairing)
                }
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
    let location: BottleLocation

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
                if let s = location.displayString {
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
