import SwiftUI

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var networkMonitor = NetworkMonitor()
    @State private var isRotating = false

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
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("PokeballIcon")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.tint)
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isRotating)
                    .onAppear { isRotating = true }
                    .onDisappear { isRotating = false }
                    .padding(.bottom, 36)

                VStack(spacing: 10) {
                    Text("Building your Pokédex")
                        .font(.title2.weight(.bold))

                    if let slug = viewModel.currentBulkSlug {
                        Text(slug.capitalized)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .id(slug)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: slug)
                    } else {
                        Text(" ").font(.title3)
                    }
                }
                .padding(.bottom, 40)

                if let progress = viewModel.bulkDetailProgress {
                    let fraction = Double(progress.current) / Double(progress.total)
                    let pct = Int(fraction * 100)

                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                            .frame(maxWidth: 300)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(
                                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(width: geo.size.width * fraction)
                                        .animation(.easeOut(duration: 0.25), value: progress.current)
                                }
                            }

                        HStack(spacing: 6) {
                            Text("\(progress.current) of \(progress.total)")
                                .monospacedDigit()
                            Text("·")
                            Text("\(pct)%")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
