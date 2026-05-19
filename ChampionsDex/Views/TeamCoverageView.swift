import SwiftUI

private struct SlotFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TeamCoverageView: View {
    var viewModel: AppViewModel

    private let allTypes = [
        "Normal", "Fire", "Water", "Electric", "Grass", "Ice",
        "Fighting", "Poison", "Ground", "Flying", "Psychic", "Bug",
        "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy"
    ]

    @State private var teamSlugs: [String?] = Array(repeating: nil, count: 6)
    @State private var queries: [String] = Array(repeating: "", count: 6)
    @State private var slotFrames: [Int: CGRect] = [:]
    @FocusState private var focusedSlot: Int?

    private var activeFiltered: [RosterEntry] {
        guard let slot = focusedSlot, !queries[slot].isEmpty else { return [] }
        return Array(viewModel.roster
            .filter { $0.name.localizedCaseInsensitiveContains(queries[slot]) }
            .prefix(6))
    }

    private var taskKey: String {
        teamSlugs.map { $0 ?? "" }.joined(separator: ",")
    }

    var body: some View {
        ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { index in
                            slotRow(index: index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .onPreferenceChange(SlotFrameKey.self) { slotFrames = $0 }

                    Divider()

                    VStack(spacing: 0) {
                        tableHeaderRow
                        ForEach(Array(allTypes.enumerated()), id: \.element) { rowIndex, type in
                            typeRow(type: type, rowIndex: rowIndex)
                        }
                    }
                }
                .task(id: taskKey) {
                    for slug in teamSlugs.compactMap({ $0 }) {
                        await viewModel.loadDetail(slug: slug)
                    }
                }

                if !activeFiltered.isEmpty,
                   let slot = focusedSlot,
                   let frame = slotFrames[slot],
                   frame != .zero
                {
                    autocompleteList
                        .padding(.horizontal, 16)
                        .offset(y: frame.maxY + 4)
                        .zIndex(10)
                }
            }
        .coordinateSpace(name: "teamView")
        .navigationTitle("Defense")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Slot row

    @ViewBuilder
    private func slotRow(index: Int) -> some View {
        HStack(spacing: 8) {
            let spriteURL: URL? = teamSlugs[index].flatMap { slug -> URL? in
                guard let urlStr = viewModel.details[slug]?.forms.first?.imageURL else { return nil }
                return URL(string: urlStr)
            }
            ZStack {
                if spriteURL != nil {
                    AsyncImage(url: spriteURL) { phase in
                        if let img = phase.image { img.resizable().scaledToFit() }
                        else {
                            Image("PokeballIcon")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color(.systemGray5))
                                .scaledToFit()
                        }
                    }
                } else {
                    Image("PokeballIcon")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color(.systemGray5))
                        .scaledToFit()
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)

            TextField("Search Pokémon...", text: $queries[index])
                .focused($focusedSlot, equals: index)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: focusedSlot) { _, newFocus in
                    if newFocus == index, teamSlugs[index] != nil {
                        queries[index] = ""
                    }
                }

            if teamSlugs[index] != nil {
                Button {
                    teamSlugs[index] = nil
                    queries[index] = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SlotFrameKey.self,
                    value: [index: geo.frame(in: .named("teamView"))]
                )
            }
        )
    }

    // MARK: Autocomplete list

    private var autocompleteList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(activeFiltered) { entry in
                    Button {
                        guard let slot = focusedSlot else { return }
                        teamSlugs[slot] = entry.id
                        queries[slot] = entry.name
                        focusedSlot = nil
                    } label: {
                        HStack(spacing: 10) {
                            let urlStr: String? = viewModel.details[entry.id]?.forms.first?.imageURL
                            let spriteURL: URL? = urlStr.flatMap { URL(string: $0) }
                            AsyncImage(url: spriteURL) { phase in
                                if let img = phase.image { img.resizable().scaledToFit() }
                                else {
                                    Image("PokeballIcon")
                                        .resizable()
                                        .renderingMode(.template)
                                        .foregroundStyle(Color(.systemGray5))
                                        .scaledToFit()
                                }
                            }
                            .frame(width: 28, height: 28)
                            Text(entry.name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    if entry.id != activeFiltered.last?.id {
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(activeFiltered.count) * 40, 220))
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    // MARK: Table header

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Type")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, height: 32, alignment: .leading)
                .padding(.leading, 8)

            ForEach(0..<6, id: \.self) { index in
                Group {
                    let spriteURL: URL? = teamSlugs[index].flatMap { slug -> URL? in
                        guard let urlStr = viewModel.details[slug]?.forms.first?.imageURL else { return nil }
                        return URL(string: urlStr)
                    }
                    if spriteURL != nil {
                        AsyncImage(url: spriteURL) { phase in
                            if let img = phase.image { img.resizable().scaledToFit().frame(width: 26, height: 26) }
                            else { Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
                        }
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 32)
            }

            Text("Weak")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 32)

            Text("Res")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 32)
        }
        .background(Color(.systemGray5))
    }

    // MARK: Type row

    @ViewBuilder
    private func typeRow(type: String, rowIndex: Int) -> some View {
        let multipliers: [Double?] = teamSlugs.map { slug in
            guard let slug else { return nil }
            guard let detail = viewModel.details[slug] else { return nil }
            return detail.forms.first?.typeMatchups[type] ?? 1.0
        }

        let filledCount = teamSlugs.filter { $0 != nil }.count
        let weakCount = multipliers.compactMap { $0 }.filter { $0 >= 2.0 }.count
        let resistCount = multipliers.compactMap { $0 }.filter { $0 <= 0.5 }.count

        HStack(spacing: 0) {
            Text(type)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(typeColor(type))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 80, height: 36, alignment: .center)

            ForEach(0..<6, id: \.self) { index in
                matchupCell(multiplier: multipliers[index], slotFilled: teamSlugs[index] != nil)
            }

            // Weak count
            Group {
                if filledCount > 0 {
                    Text(weakCount > 0 ? "\(weakCount)" : "")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(weakCount > 0 ? .white : .clear)
                        .frame(width: 44, height: 36)
                        .background(weakCount > 0 ? Color.red.opacity(countOpacity(weakCount)) : Color(.systemGray6).opacity(0.4))
                } else {
                    Text("")
                        .frame(width: 44, height: 36)
                        .background(Color(.systemGray6).opacity(0.4))
                }
            }

            // Resist count
            Group {
                if filledCount > 0 {
                    Text(resistCount > 0 ? "\(resistCount)" : "")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(resistCount > 0 ? .white : .clear)
                        .frame(width: 44, height: 36)
                        .background(resistCount > 0 ? Color.green.opacity(countOpacity(resistCount)) : Color(.systemGray6).opacity(0.4))
                } else {
                    Text("")
                        .frame(width: 44, height: 36)
                        .background(Color(.systemGray6).opacity(0.4))
                }
            }
        }
        .background(rowIndex % 2 == 0 ? Color(.systemBackground) : Color(.systemGray6).opacity(0.25))
    }

    // MARK: Matchup cell

    @ViewBuilder
    private func matchupCell(multiplier: Double?, slotFilled: Bool) -> some View {
        if !slotFilled {
            Text("—")
                .font(.system(size: 10))
                .foregroundStyle(Color(.systemGray4))
                .frame(width: 40, height: 36)
                .background(Color(.systemGray6).opacity(0.3))
        } else if let m = multiplier {
            let (label, bg) = cellStyle(for: m)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 40, height: 36)
                .background(bg)
        } else {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 40, height: 36)
        }
    }

    // MARK: Helpers

    private func countOpacity(_ count: Int) -> Double {
        guard count > 0 else { return 0 }
        return 0.3 + Double(count - 1) / 5.0 * 0.7
    }

    private func cellStyle(for multiplier: Double) -> (String, Color) {
        switch multiplier {
        case 0:    return ("✕",  Color.blue.opacity(0.25))
        case 0.25: return ("¼×", Color.green.opacity(0.55))
        case 0.5:  return ("½×", Color.green.opacity(0.3))
        case 2.0:  return ("2×", Color.orange.opacity(0.45))
        case 4.0:  return ("4×", Color.red.opacity(0.55))
        default:   return ("",   Color.clear)
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "Normal":   return Color(red: 0.65, green: 0.65, blue: 0.47)
        case "Fire":     return Color(red: 0.94, green: 0.50, blue: 0.20)
        case "Water":    return Color(red: 0.39, green: 0.60, blue: 0.94)
        case "Electric": return Color(red: 0.80, green: 0.68, blue: 0.10)
        case "Grass":    return Color(red: 0.48, green: 0.78, blue: 0.32)
        case "Ice":      return Color(red: 0.40, green: 0.75, blue: 0.75)
        case "Fighting": return Color(red: 0.76, green: 0.19, blue: 0.20)
        case "Poison":   return Color(red: 0.63, green: 0.25, blue: 0.63)
        case "Ground":   return Color(red: 0.88, green: 0.75, blue: 0.42)
        case "Flying":   return Color(red: 0.55, green: 0.47, blue: 0.82)
        case "Psychic":  return Color(red: 0.97, green: 0.35, blue: 0.53)
        case "Bug":      return Color(red: 0.55, green: 0.61, blue: 0.10)
        case "Rock":     return Color(red: 0.71, green: 0.63, blue: 0.31)
        case "Ghost":    return Color(red: 0.45, green: 0.34, blue: 0.59)
        case "Dragon":   return Color(red: 0.44, green: 0.22, blue: 0.82)
        case "Dark":     return Color(red: 0.44, green: 0.34, blue: 0.27)
        case "Steel":    return Color(red: 0.58, green: 0.58, blue: 0.68)
        case "Fairy":    return Color(red: 0.90, green: 0.47, blue: 0.62)
        default:         return .gray
        }
    }
}
