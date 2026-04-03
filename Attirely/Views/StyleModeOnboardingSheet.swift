import SwiftUI

struct StyleModeOnboardingSheet: View {
    @Binding var isPresented: Bool
    let onConfirm: (StyleModePreference) -> Void

    @State private var selected: StyleModePreference = .improve

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How should Attirely suggest outfits?")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("You can change this any time in Profile settings.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    ForEach(StyleModePreference.allCases, id: \.self) { mode in
                        styleModeCard(mode)
                    }
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Style Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConfirm(selected)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.champagne)
                }
            }
        }
    }

    private func styleModeCard(_ mode: StyleModePreference) -> some View {
        Button {
            selected = mode
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected == mode ? Theme.champagne : Theme.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(cardDescription(mode))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding()
            .background(selected == mode ? Theme.cardFill : Theme.cardFill.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected == mode ? Theme.champagne : Theme.cardBorder, lineWidth: selected == mode ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardDescription(_ mode: StyleModePreference) -> String {
        switch mode {
        case .improve:
            "Steers every outfit toward polished, classic looks — preppy, business casual, smart casual. Great for building a more refined wardrobe presence."
        case .expand:
            "Reads your wardrobe and saved outfits to identify your personal style, then generates suggestions that feel authentically you. Gets better with more data."
        }
    }
}
