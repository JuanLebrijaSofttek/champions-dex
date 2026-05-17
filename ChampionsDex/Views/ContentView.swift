import SwiftUI

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var networkMonitor = NetworkMonitor()
    @State private var hasShownBulkPrompt = false
    @State private var showBulkPrompt = false

    var body: some View {
        Group {
            switch viewModel.appState {
            case .launching:
                launchScreen(icon: "arrow.down.circle", message: viewModel.loadingMessage)

            case .downloadingRoster:
                downloadingScreen

            case .noDataOffline:
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No data available. Connect to the internet to get started.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            default:
                TabView {
                    PokedexGridView(viewModel: viewModel, networkMonitor: networkMonitor)
                        .tabItem { Label("Pokédex", systemImage: "list.bullet") }
                    TeamCoverageView(viewModel: viewModel)
                        .tabItem { Label("Team", systemImage: "person.3.fill") }
                    SettingsView(viewModel: viewModel, networkMonitor: networkMonitor)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .onChange(of: viewModel.appState) { _, newState in
                    if case .ready = newState { triggerBulkPromptIfNeeded() }
                }
                .sheet(isPresented: $showBulkPrompt) {
                    BulkDownloadPromptView(
                        onDownloadAll: { showBulkPrompt = false; viewModel.startBulkDownload() },
                        onBrowseFirst: { showBulkPrompt = false }
                    )
                    .presentationDetents([.medium])
                }
            }
        }
        .task {
            await viewModel.launch(networkMonitor: networkMonitor)
        }
    }

    // MARK: Loading screens

    @ViewBuilder
    private func launchScreen(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .animation(.default, value: message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var downloadingScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Downloading Pokémon")
                    .font(.title2.weight(.semibold))

                if let slug = viewModel.currentDownloadingSlug {
                    Text(slug)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.default, value: slug)
                }
            }

            if let progress = viewModel.downloadProgress {
                VStack(spacing: 10) {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)

                    HStack(spacing: 16) {
                        Text("\(progress.current) of \(progress.total)")
                            .monospacedDigit()
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(formattedBytes(viewModel.bytesDownloaded))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func formattedBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: Bulk prompt trigger

    private func triggerBulkPromptIfNeeded() {
        guard !hasShownBulkPrompt, networkMonitor.isConnected else { return }
        let allCached = viewModel.roster.allSatisfy { $0.iconCached }
        guard allCached, !viewModel.roster.isEmpty else { return }
        let anyDetailMissing = viewModel.roster.contains { !PersistenceManager.shared.detailExists(slug: $0.id) }
        guard anyDetailMissing else { return }
        hasShownBulkPrompt = true
        showBulkPrompt = true
    }
}

struct BulkDownloadPromptView: View {
    let onDownloadAll: () -> Void
    let onBrowseFirst: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Download all Pokémon data?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Get stats, moves, and type info for all Pokémon now, or load them one at a time as you browse.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button("Download All", action: onDownloadAll)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button("Browse First", action: onBrowseFirst)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
}
