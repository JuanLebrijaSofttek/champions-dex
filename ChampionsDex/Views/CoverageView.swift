import SwiftUI

struct CoverageView: View {
    var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                NavigationLink {
                    TypeEffectivenessView(viewModel: viewModel)
                } label: {
                    coverageCard(
                        title: "Offense",
                        subtitle: "See which Pokémon a move type hits and how hard",
                        icon: "bolt.fill"
                    )
                }

                NavigationLink {
                    TeamCoverageView(viewModel: viewModel)
                } label: {
                    coverageCard(
                        title: "Defense",
                        subtitle: "Analyze type weaknesses across your team",
                        icon: "shield.fill"
                    )
                }

                Spacer()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .navigationTitle("Coverage")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func coverageCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
