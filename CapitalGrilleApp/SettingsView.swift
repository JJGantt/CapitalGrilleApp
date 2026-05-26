import SwiftUI

struct SettingsView: View {
    @ObservedObject var wineStore: WineStore
    @Environment(\.dismiss) var dismiss
    @State private var backend: Backend = Backend.current
    @State private var model: AIModel = AIModel.current
    @State private var newAreaName: String = ""
    @State private var renameTarget: WineArea?
    @State private var renameValue: String = ""
    @State private var busy: Bool = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    Picker("Backend", selection: $backend) {
                        Text("Mac").tag(Backend.mac)
                        Text("API").tag(Backend.api)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: backend) { new in Backend.current = new }
                }

                Section("Model") {
                    Picker("Model", selection: $model) {
                        ForEach(AIModel.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: model) { new in AIModel.current = new }
                }

                Section("Areas") {
                    if !wineStore.areas.isEmpty {
                        ForEach(wineStore.areas) { area in
                            HStack {
                                Text(area.name)
                                Spacer()
                                Button {
                                    renameTarget = area
                                    renameValue = area.name
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                                Button(role: .destructive) {
                                    Task { await remove(area: area.name) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                                .padding(.leading, 12)
                            }
                        }
                    }
                    HStack {
                        TextField("New area", text: $newAreaName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onSubmit { Task { await add() } }
                        Button(action: { Task { await add() } }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newAreaName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                }

                if let err = errorMsg {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await wineStore.refreshFromSupabase() }
            .alert("Rename area", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameValue)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") { Task { await rename() } }
            }
        }
    }

    private func add() async {
        let name = newAreaName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        busy = true; errorMsg = nil
        do { try await wineStore.addArea(name); newAreaName = "" }
        catch { errorMsg = error.localizedDescription }
        busy = false
    }

    private func rename() async {
        guard let target = renameTarget else { return }
        let new = renameValue.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != target.name else { renameTarget = nil; return }
        busy = true; errorMsg = nil
        do { try await wineStore.renameArea(target.name, to: new) }
        catch { errorMsg = error.localizedDescription }
        renameTarget = nil
        busy = false
    }

    private func remove(area: String) async {
        busy = true; errorMsg = nil
        do { try await wineStore.removeArea(area) }
        catch { errorMsg = error.localizedDescription }
        busy = false
    }
}
