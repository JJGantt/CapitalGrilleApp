import SwiftUI

struct WatchSettingsView: View {
    @State private var backend = Backend.current
    @State private var model = AIModel.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Backend")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("Backend", selection: $backend) {
                    ForEach(Backend.allCases, id: \.self) { b in
                        Text(b.label).tag(b)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 56)
                .onChange(of: backend) { _, new in Backend.current = new }

                Text("Model")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("Model", selection: $model) {
                    ForEach(AIModel.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 56)
                .onChange(of: model) { _, new in AIModel.current = new }

                if backend == .mac {
                    Text("Mac backend needs the iPhone nearby with Tailscale active. Falls back to API automatically if unreachable.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(8)
        }
        .navigationTitle("Settings")
    }
}
