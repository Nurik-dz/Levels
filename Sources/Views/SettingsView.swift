import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(MixerModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmReset = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Levels at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            } header: { Text("General") }

            Section {
                LabeledContent("App audio") {
                    Button("Open Privacy Settings") { Permissions.openPrivacySettings() }
                }
                Text("Levels needs permission to hear app audio, under Privacy & Security, Screen & System Audio Recording. It only reads sound to measure and change it. Nothing is recorded or sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Permission") }

            Section {
                if model.remembered.isEmpty {
                    Text("Apps you change appear here, so a quiet app set to 0% is never lost.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.remembered, id: \.id) { item in
                    LabeledContent {
                        Button("Reset") { withAnimation(.smooth) { model.reset(item.id) } }
                            .buttonStyle(.glass).controlSize(.small)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(item.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Reset All App Settings…", role: .destructive) { confirmReset = true }
                    .disabled(model.remembered.isEmpty)
                    .confirmationDialog("Reset every app to its original sound?", isPresented: $confirmReset) {
                        Button("Reset All", role: .destructive) { model.resetAll() }
                    } message: { Text("Volumes, mutes, equalizers and output choices go back to normal.") }
            } header: { Text("Apps you changed") }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            } header: { Text("About") }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }
}
