import SwiftUI

struct PokemonCell: View {
    let entry: RosterEntry
    var viewModel: AppViewModel

    private var dexNumber: Int? { viewModel.details[entry.id]?.number }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let img = viewModel.icons[entry.id] {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                            .frame(width: 72, height: 72)

                        VStack(spacing: 2) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color(.systemGray3))
                            if entry.iconCached {
                                // Icon file exists but not yet loaded into memory — neutral gray
                                EmptyView()
                            } else {
                                // Never fetched
                                Text("?")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                        }
                    }
                }
            }

            Text(entry.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            if let number = dexNumber {
                Text("#\(number)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // Reserve space so cells stay the same height
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(width: 90, height: 110)
        .task {
            if entry.iconCached {
                await viewModel.loadIconIfNeeded(slug: entry.id)
            }
        }
    }
}
