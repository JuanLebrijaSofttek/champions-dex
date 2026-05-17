import SwiftUI

struct PokemonDetailView: View {
    let slug: String
    var viewModel: AppViewModel

    @State private var selectedFormIndex = 0
    @State private var movesExpanded = false
    @State private var loadFailed = false
    @State private var showRefreshConfirm = false

    private static let typeColors: [String: Color] = [
        "Normal":   Color(red: 0.659, green: 0.655, blue: 0.478),
        "Fire":     Color(red: 0.933, green: 0.506, blue: 0.188),
        "Water":    Color(red: 0.388, green: 0.565, blue: 0.941),
        "Electric": Color(red: 0.969, green: 0.816, blue: 0.173),
        "Grass":    Color(red: 0.478, green: 0.780, blue: 0.298),
        "Ice":      Color(red: 0.588, green: 0.851, blue: 0.839),
        "Fighting": Color(red: 0.761, green: 0.180, blue: 0.157),
        "Poison":   Color(red: 0.639, green: 0.243, blue: 0.631),
        "Ground":   Color(red: 0.886, green: 0.749, blue: 0.396),
        "Flying":   Color(red: 0.663, green: 0.561, blue: 0.953),
        "Psychic":  Color(red: 0.976, green: 0.337, blue: 0.529),
        "Bug":      Color(red: 0.651, green: 0.725, blue: 0.102),
        "Rock":     Color(red: 0.714, green: 0.631, blue: 0.208),
        "Ghost":    Color(red: 0.451, green: 0.341, blue: 0.592),
        "Dragon":   Color(red: 0.435, green: 0.208, blue: 0.988),
        "Dark":     Color(red: 0.439, green: 0.341, blue: 0.275),
        "Steel":    Color(red: 0.718, green: 0.718, blue: 0.808),
        "Fairy":    Color(red: 0.839, green: 0.522, blue: 0.678),
    ]

    var body: some View {
        Group {
            if let detail = viewModel.details[slug] {
                loadedView(detail: detail)
            } else if loadFailed {
                errorView
            } else {
                loadingScreen
            }
        }
        .task { await load() }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Loading screen

    @ViewBuilder
    private var loadingScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            if let img = viewModel.icons[slug] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(.systemGray3))
            }

            Text("Loading \(slug.capitalized)...")
                .font(.title3.weight(.semibold))

            ProgressView(value: viewModel.detailLoadingProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)

            Text(viewModel.detailLoadingLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.default, value: viewModel.detailLoadingLabel)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error view

    @ViewBuilder
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Couldn't load data. Check your connection and try again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Loaded view

    @ViewBuilder
    private func loadedView(detail: PokemonDetail) -> some View {
        let form = detail.forms.indices.contains(selectedFormIndex) ? detail.forms[selectedFormIndex] : detail.forms[0]

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header — sprite + name + number
                VStack(spacing: 12) {
                    formSprite(url: form.imageURL, slug: slug)

                    VStack(spacing: 4) {
                        Text(detail.name)
                            .font(.largeTitle.weight(.bold))
                        Text("#\(detail.number)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    if let gender = detail.genderRatio {
                        HStack(spacing: 8) {
                            genderPill("♂", percent: gender.male, color: .blue)
                            genderPill("♀", percent: gender.female, color: .pink)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Form picker
                if detail.forms.count > 1 {
                    Picker("Form", selection: $selectedFormIndex) {
                        ForEach(detail.forms.indices, id: \.self) { i in
                            Text(detail.forms[i].formName).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedFormIndex) { _, _ in movesExpanded = false }
                }

                // Info row: types | height | weight | classification
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            ForEach(form.types, id: \.self) { typePill($0) }
                        }
                        if !form.classification.isEmpty {
                            Text(form.classification)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if !form.height.isEmpty {
                            Label(form.height, systemImage: "arrow.up.and.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !form.weight.isEmpty {
                            Label(form.weight, systemImage: "scalemass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Base Stats
                sectionHeader("Base Stats")
                statsView(stats: form.stats)

                // Abilities
                if !form.abilities.isEmpty {
                    sectionHeader("Abilities")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(form.abilities, id: \.name) { ability in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ability.name)
                                    .font(.subheadline.weight(.semibold))
                                if !ability.description.isEmpty {
                                    Text(ability.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Type Matchups
                let weaknesses  = form.typeMatchups.filter { $0.value >= 2.0 }
                let resistances = form.typeMatchups.filter { $0.value > 0 && $0.value < 1.0 }
                let immunities  = form.typeMatchups.filter { $0.value == 0.0 }

                if !weaknesses.isEmpty || !resistances.isEmpty || !immunities.isEmpty {
                    sectionHeader("Type Matchups")
                    matchupSubsection("Weaknesses",  entries: weaknesses)
                    matchupSubsection("Resistances", entries: resistances)
                    matchupSubsection("Immunities",  entries: immunities)
                }

                // Moves
                if !form.moves.isEmpty {
                    HStack {
                        sectionHeader("Moves")
                        Spacer()
                        Button(movesExpanded ? "Hide moves" : "Show moves (\(form.moves.count))") {
                            movesExpanded.toggle()
                        }
                        .font(.caption)
                    }

                    if movesExpanded {
                        LazyVStack(spacing: 0) {
                            ForEach(form.moves, id: \.name) { move in
                                moveRow(move)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showRefreshConfirm = true } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .alert("Refresh \(detail.name)?", isPresented: $showRefreshConfirm) {
            Button("Refresh", role: .destructive) {
                viewModel.clearDetail(slug: slug)
                Task { await load() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached data will be cleared and re-fetched from the web.")
        }
    }

    // MARK: Form sprite

    @ViewBuilder
    private func formSprite(url: String, slug: String) -> some View {
        if !url.isEmpty, let remoteURL = URL(string: url) {
            AsyncImage(url: remoteURL) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else if phase.error != nil {
                    iconPlaceholder(slug: slug)
                } else {
                    ProgressView()
                        .frame(width: 120, height: 120)
                }
            }
            .frame(width: 120, height: 120)
        } else {
            iconPlaceholder(slug: slug)
        }
    }

    @ViewBuilder
    private func iconPlaceholder(slug: String) -> some View {
        if let img = viewModel.icons[slug] {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
        } else {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color(.systemGray3))
                .frame(width: 120, height: 120)
        }
    }

    // MARK: Gender pill

    @ViewBuilder
    private func genderPill(_ symbol: String, percent: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(symbol)
            Text("\(Int(percent))%")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12).fill(color))
    }

    // MARK: Section header

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top, 4)
    }

    // MARK: Type pill

    @ViewBuilder
    private func typePill(_ typeName: String) -> some View {
        Text(typeName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12).fill(Self.typeColors[typeName] ?? .gray))
    }

    // MARK: Stats

    @ViewBuilder
    private func statsView(stats: Stats) -> some View {
        let rows: [(String, Int)] = [
            ("HP",      stats.hp),
            ("Attack",  stats.attack),
            ("Defense", stats.defense),
            ("Sp. Atk", stats.specialAttack),
            ("Sp. Def", stats.specialDefense),
            ("Speed",   stats.speed),
        ]
        VStack(spacing: 6) {
            ForEach(rows, id: \.0) { label, value in
                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption)
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(statColor(value))
                            .frame(width: geo.size.width * CGFloat(value) / 255.0)
                    }
                    .frame(height: 14)
                    Text("\(value)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
            }
            HStack(spacing: 8) {
                Text("Total")
                    .font(.caption.weight(.semibold))
                    .frame(width: 56, alignment: .trailing)
                Spacer()
                Text("\(stats.total)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    private func statColor(_ value: Int) -> Color {
        if value < 60 { return .red }
        if value < 90 { return .yellow }
        return .green
    }

    // MARK: Type matchups

    @ViewBuilder
    private func matchupSubsection(_ title: String, entries: [String: Double]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(entries.sorted(by: { $0.key < $1.key }), id: \.key) { typeName, mult in
                        ZStack(alignment: .topTrailing) {
                            typePill(typeName)
                            Text(multLabel(mult))
                                .font(.system(size: 9).weight(.bold))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .offset(x: 4, y: -4)
                        }
                    }
                }
            }
        }
    }

    private func multLabel(_ mult: Double) -> String {
        switch mult {
        case 0:    return "×0"
        case 0.25: return "×¼"
        case 0.5:  return "×½"
        case 2:    return "×2"
        case 4:    return "×4"
        default:   return "×\(mult)"
        }
    }

    // MARK: Move row

    @ViewBuilder
    private func moveRow(_ move: Move) -> some View {
        HStack(spacing: 8) {
            Text(move.name)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            typePill(move.type)
            Text(categoryIcon(move.category))
                .font(.caption)
                .frame(width: 20)
            Group {
                Text(move.power.map { "\($0)" } ?? "—")
                Text(move.accuracy.map { "\($0)" } ?? "—")
                Text("\(move.pp)")
            }
            .font(.caption.monospacedDigit())
            .frame(width: 28)
        }
        .padding(.vertical, 6)
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Physical": return "⚔️"
        case "Special":  return "✨"
        default:         return "—"
        }
    }

    // MARK: Load

    private func load() async {
        print("🔍⏳ [Detail] load() START slug=\(slug)")
        guard viewModel.details[slug] == nil else {
            print("🔍✅ [Detail] already in memory")
            return
        }
        await viewModel.loadDetail(slug: slug)
        if viewModel.details[slug] == nil { loadFailed = true }
    }
}

// MARK: FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
