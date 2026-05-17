import SwiftUI

struct SettingsView: View {
    var viewModel: AppViewModel
    var networkMonitor: NetworkMonitor

    @State private var showClearAllConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Cache") {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Clear All Data?", isPresented: $showClearAllConfirm) {
                Button("Clear", role: .destructive) {
                    viewModel.clearAllDataAndRelaunch(networkMonitor: networkMonitor)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All cached Pokémon data, icons, and the roster will be deleted and re-downloaded.")
            }
        }
    }
}
