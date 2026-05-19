import SwiftUI

private let allTypes = [
    "Normal", "Fire", "Water", "Electric", "Grass", "Ice",
    "Fighting", "Poison", "Ground", "Flying", "Psychic", "Bug",
    "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy"
]

struct TypeEffectivenessView: View {
    var viewModel: AppViewModel

    @State private var selectedTypes: [String] = []

    private struct FormRow: Identifiable {
        let id: String
        let entry: RosterEntry
        let imageURL: URL?
        let typeMatchups: [String: Double]
    }

    private var allRows: [FormRow] {
        viewModel.roster.flatMap { entry -> [FormRow] in
            guard let detail = viewModel.details[entry.id] else { return [] }
            return detail.forms.enumerated().compactMap { index, form in
                guard form.stats.total > 0 else { return nil }
                let url: URL? = form.imageURL.isEmpty ? nil : URL(string: form.imageURL)
                return FormRow(
                    id: "\(entry.id)-\(index)",
                    entry: entry,
                    imageURL: url,
                    typeMatchups: form.typeMatchups
                )
            }
        }
    }

    private func combinedMultiplier(for row: FormRow) -> Double {
        selectedTypes.map { row.typeMatchups[$0] ?? 1.0 }.max() ?? 1.0
    }

    private struct Sections {
        let immune: [FormRow]
        let barely: [FormRow]
        let notVery: [FormRow]
        let normal: [FormRow]
        let superEffective: [FormRow]
    }

    private var sections: Sections {
        var immune: [FormRow] = []
        var barely: [FormRow] = []
        var notVery: [FormRow] = []
        var normal: [FormRow] = []
        var superEffective: [FormRow] = []
        for row in allRows {
            let m = combinedMultiplier(for: row)
            if m == 0.0 {
                immune.append(row)
            } else if m <= 0.25 {
                barely.append(row)
            } else if m < 1.0 {
                notVery.append(row)
            } else if m == 1.0 {
                normal.append(row)
            } else {
                superEffective.append(row)
            }
        }
        return Sections(immune: immune, barely: barely, notVery: notVery, normal: normal, superEffective: superEffective)
    }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        VStack(spacing: 0) {
                summaryBar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                            ForEach(allTypes, id: \.self) { type in
                                typeButton(type)
                            }
                        }
                        .padding(16)

                        Divider()

                        if allRows.isEmpty {
                            Text("Download Pokémon data first via Settings → Refresh.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity)
                        } else {
                            let s = sections
                            sectionBlock("No Effect", count: s.immune.count, rows: s.immune)
                            sectionBlock("Barely Effective", count: s.barely.count, rows: s.barely)
                            sectionBlock("Not Very Effective", count: s.notVery.count, rows: s.notVery)
                            sectionBlock("Normal Effectiveness", count: s.normal.count, rows: s.normal)
                            sectionBlock("Super Effective", count: s.superEffective.count, rows: s.superEffective)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Offense")
            .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Type button

    @ViewBuilder
    private func typeButton(_ type: String) -> some View {
        let isSelected = selectedTypes.contains(type)
        let maxReached = selectedTypes.count >= 4 && !isSelected
        Button {
            if let idx = selectedTypes.firstIndex(of: type) {
                selectedTypes.remove(at: idx)
            } else if selectedTypes.count < 4 {
                selectedTypes.append(type)
            }
        } label: {
            Text(type.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(typeColor(type).opacity(maxReached ? 0.35 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .disabled(maxReached)
    }

    // MARK: - Summary bar (sticky)

    private var summaryBar: some View {
        let s = sections
        let items: [(Int, String)] = [
            (s.immune.count,        "No Effect"),
            (s.barely.count,        "Barely"),
            (s.notVery.count,       "Not Very"),
            (s.normal.count,        "Normal"),
            (s.superEffective.count,"Super Eff."),
        ]
        return HStack(spacing: 0) {
            ForEach(items, id: \.1) { count, label in
                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.6))
    }

    // MARK: - Section block

    @ViewBuilder
    private func sectionBlock(_ title: String, count: Int, rows: [FormRow]) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text("(\(count))")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, rows.isEmpty ? 14 : 8)

        if !rows.isEmpty {
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(rows) { row in
                    spriteImage(url: row.imageURL)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }

        Divider()
            .padding(.top, rows.isEmpty ? 0 : 8)
    }

    // MARK: - Sprite icon

    @ViewBuilder
    private func spriteImage(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let img = phase.image {
                img.resizable().scaledToFit()
            } else {
                Image("PokeballIcon")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(.systemGray5))
                    .scaledToFit()
            }
        }
        .frame(width: 44, height: 44)
    }

    // MARK: - Type colors (matches TeamCoverageView)

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
