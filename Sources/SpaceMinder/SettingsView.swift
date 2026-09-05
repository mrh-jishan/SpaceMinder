import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: StorageViewModel

    var body: some View {
        Form {
            Section("Automation") {
                Toggle("Open SpaceMinder when I log in", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _ in model.updateLoginItem() }
                Text("macOS manages this login item. SpaceMinder never performs cleanup automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Custom scan folders") {
                Text("Custom locations are shown on the dashboard for inspection only. They cannot be selected for automatic cleanup.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.customPaths, id: \.self) { url in
                    HStack { Text(url.path).lineLimit(1); Spacer(); Button("Remove") { model.customPaths.removeAll { $0 == url }; Task { await model.scan() } } }
                }
                Button("Add folder…") { model.addCustomPath() }
            }
            Section("Privacy") {
                Text("All file analysis, cleanup decisions, and history stay on this Mac. SpaceMinder has no accounts, analytics, or network features.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
    }
}
