import SwiftUI

// MARK: - StatColumn

private enum StatColumn: CaseIterable, Hashable {
    case hp, attack, defense, specialAttack, specialDefense, speed, total

    var label: String {
        switch self {
        case .hp:             return "HP"
        case .attack:         return "Atk"
        case .defense:        return "Def"
        case .specialAttack:  return "SpA"
        case .specialDefense: return "SpD"
        case .speed:          return "Spe"
        case .total:          return "Tot"
        }
    }

    var keyPath: KeyPath<Stats, Int> {
        switch self {
        case .hp:             return \.hp
        case .attack:         return \.attack
        case .defense:        return \.defense
        case .specialAttack:  return \.specialAttack
        case .specialDefense: return \.specialDefense
        case .speed:          return \.speed
        case .total:          return \.total
        }
    }

    var width: CGFloat { 36 }
}

// MARK: - StatsDexView

struct StatsDexView: View {
    var viewModel: AppViewModel

    @State private var sortColumn: StatColumn? = nil
    @State private var sortDescending: Bool = true

    // MARK: FormRow

    private struct FormRow: Identifiable {
        let id: String
        let entry: RosterEntry
        let stats: Stats?
        let imageURL: URL?
        let formLabel: String?  // nil for base/single form; "Mega X", "Alolan", etc. for alternates
    }

    private var allRows: [FormRow] {
        viewModel.roster.flatMap { entry -> [FormRow] in
            guard let detail = viewModel.details[entry.id] else {
                return [FormRow(id: entry.id, entry: entry, stats: nil, imageURL: nil, formLabel: nil)]
            }
            return detail.forms.enumerated().map { formIndex, form in
                let prefix = form.formName
                    .replacingOccurrences(of: entry.name, with: "")
                    .trimmingCharacters(in: .whitespaces)
                let label: String? = (detail.forms.count > 1 && formIndex > 0 && !prefix.isEmpty) ? prefix : nil
                let urlStr: String? = form.imageURL.isEmpty ? nil : form.imageURL
                let url: URL? = urlStr.flatMap { URL(string: $0) }
                return FormRow(
                    id: "\(entry.id)-\(formIndex)",
                    entry: entry,
                    stats: form.stats,
                    imageURL: url,
                    formLabel: label
                )
            }
        }
    }

    private var displayedRows: [FormRow] {
        guard let col = sortColumn else { return allRows }
        return allRows.sorted { a, b in
            switch (a.stats, b.stats) {
            case (nil, nil): return false
            case (nil, _):   return false
            case (_, nil):   return true
            case let (sa?, sb?):
                let va = sa[keyPath: col.keyPath]
                let vb = sb[keyPath: col.keyPath]
                return sortDescending ? va > vb : va < vb
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(displayedRows.enumerated()), id: \.element.id) { idx, row in
                            statRow(row: row, rowIndex: idx)
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 40, height: 28)

            Text("Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(StatColumn.allCases, id: \.self) { col in
                sortButton(col)
            }
        }
        .padding(.horizontal, 10)
        .background(Color(.systemGray5))
    }

    @ViewBuilder
    private func sortButton(_ col: StatColumn) -> some View {
        let isActive = sortColumn == col
        Button { handleTap(col) } label: {
            HStack(spacing: 1) {
                Text(col.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                if isActive {
                    Image(systemName: sortDescending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: col.width, height: 28)
            .background(isActive ? Color(.systemGray4).opacity(0.4) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: Stat row

    private func statRow(row: FormRow, rowIndex: Int) -> some View {
        let bg: Color = rowIndex % 2 == 0 ? Color(.systemBackground) : Color(.systemGray6).opacity(0.25)

        return HStack(spacing: 0) {
            spriteImage(url: row.imageURL)
                .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.entry.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                if let label = row.formLabel {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(StatColumn.allCases, id: \.self) { col in
                self.statCell(stats: row.stats, col: col)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(bg)
    }

    @ViewBuilder
    private func spriteImage(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let img = phase.image {
                img.resizable().scaledToFit()
            } else {
                Circle().fill(Color(.systemGray5))
            }
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private func statCell(stats: Stats?, col: StatColumn) -> some View {
        if let s = stats {
            Text("\(s[keyPath: col.keyPath])")
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(col == .total ? Color.primary : Color.secondary)
                .frame(width: col.width, alignment: .trailing)
        } else {
            Text("—")
                .font(.system(size: 14))
                .foregroundStyle(Color(.systemGray4))
                .frame(width: col.width, alignment: .trailing)
        }
    }

    // MARK: Sort logic

    private func handleTap(_ col: StatColumn) {
        if sortColumn == col {
            if sortDescending {
                sortDescending = false
            } else {
                sortColumn = nil
            }
        } else {
            sortColumn = col
            sortDescending = true
        }
    }
}
