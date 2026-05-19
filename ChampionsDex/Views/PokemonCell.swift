import SwiftUI

struct PokemonCell: View {
    let entry: RosterEntry
    var viewModel: AppViewModel

    private var dexNumber: Int? { viewModel.details[entry.id]?.number }
    private var spriteURL: URL? {
        guard let urlStr = viewModel.details[entry.id]?.forms.first?.imageURL,
              !urlStr.isEmpty else { return nil }
        return URL(string: urlStr)
    }

    var body: some View {
        VStack(spacing: 2) {
            AsyncImage(url: spriteURL) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else {
                    Image("PokeballIcon")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color(.systemGray6))
                        .scaledToFit()
                }
            }
            .frame(width: 72, height: 72)

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
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(width: 90, height: 110)
    }
}
