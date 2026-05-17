import SwiftUI

enum SortOrder: String, CaseIterable {
    case defaultOrder = "Default"
    case nameAZ       = "Name A→Z"
    case nameZA       = "Name Z→A"
    case dexNumber    = "Dex #"
}

struct PokedexGridView: View {
    var viewModel: AppViewModel
    var networkMonitor: NetworkMonitor

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .defaultOrder

    private var displayedRoster: [RosterEntry] {
        var list = searchText.isEmpty
            ? viewModel.roster
            : viewModel.roster.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        switch sortOrder {
        case .defaultOrder: break
        case .nameAZ: list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameZA: list.sort { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .dexNumber:
            list.sort {
                let a = viewModel.details[$0.id]?.number ?? Int.max
                let b = viewModel.details[$1.id]?.number ?? Int.max
                return a < b
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Offline banner
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("You're offline — showing cached data")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.85))
                    .foregroundStyle(.black)
                }

                // Search bar + sort button row
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search", text: $searchText)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: sortOrder == .defaultOrder
                              ? "arrow.up.arrow.down"
                              : "arrow.up.arrow.down.circle.fill")
                            .font(.system(size: 17))
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

                Divider()

                // Grid content
                if displayedRoster.isEmpty && !searchText.isEmpty {
                    Spacer()
                    Text("No Pokémon found")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                            ForEach(displayedRoster) { entry in
                                NavigationLink(destination: PokemonDetailView(slug: entry.id, viewModel: viewModel)) {
                                    PokemonCell(entry: entry, viewModel: viewModel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Pokémon Champions")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
