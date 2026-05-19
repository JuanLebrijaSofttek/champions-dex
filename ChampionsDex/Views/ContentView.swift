import SwiftUI

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var networkMonitor = NetworkMonitor()

    var body: some View {
        Group {
            switch viewModel.appState {
            case .launching:
                launchScreen(icon: "arrow.down.circle", message: viewModel.loadingMessage)

            case .loadingDetails:
                detailLoadingScreen

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
                    CoverageView(viewModel: viewModel)
                        .tabItem { Label("Coverage", systemImage: "shield.lefthalf.filled.slash") }
                    StatsDexView(viewModel: viewModel)
                        .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    SettingsView(viewModel: viewModel, networkMonitor: networkMonitor)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
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
    private var detailLoadingScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("PokeballIcon")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)

            VStack(spacing: 8) {
                Text("Loading Pokémon Data")
                    .font(.title2.weight(.semibold))

                if let slug = viewModel.currentBulkSlug {
                    Text(slug.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.default, value: slug)
                }
            }

            if let progress = viewModel.bulkDetailProgress {
                VStack(spacing: 10) {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)

                    Text("\(progress.current) of \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                ProgressView()
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
