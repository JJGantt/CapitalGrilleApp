import SwiftUI

struct WatchSettingsView: View {
    @State private var backend = Backend.current
    @State private var model = AIModel.current
    @State private var hasKey = APIKeyStore.current != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(title: "API key") {
                    Text(hasKey ? "Set (from iPhone)" : "Not set — open Settings on iPhone")
                        .font(.system(size: 12))
                        .foregroundColor(hasKey ? .white : .red)
                }

                section(title: "Backend") {
                    ForEach(Backend.allCases, id: \.self) { b in
                        radioRow(label: b.label, selected: backend == b) {
                            backend = b
                            Backend.current = b
                        }
                    }
                }

                section(title: "Model") {
                    ForEach(AIModel.allCases) { m in
                        radioRow(label: m.label, selected: model == m) {
                            model = m
                            AIModel.current = m
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            VStack(spacing: 2) {
                content()
            }
        }
    }

    @ViewBuilder
    private func radioRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(selected ? .accentColor : .secondary)
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
