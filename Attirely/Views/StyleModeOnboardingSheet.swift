import SwiftUI

struct StyleModeOnboardingSheet: View {
    @Binding var isPresented: Bool
    let onConfirm: (StyleModePreference, StyleDirection?) -> Void

    @State private var selectedMode: StyleModePreference = .improve
    @State private var selectedDirection: StyleDirection = .preppy

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

                    // Mode cards
                    ForEach(StyleModePreference.allCases, id: \.self) { mode in
                        modeCard(mode)
                    }

                    // Direction picker — only visible when Improve is selected
                    if selectedMode == .improve {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pick a style direction")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)

                            ForEach(StyleDirection.allCases, id: \.self) { dir in
                                directionCard(dir)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: selectedMode)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Style Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConfirm(selectedMode, selectedMode == .improve ? selectedDirection : nil)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.champagne)
                }
            }
        }
    }

    private func modeCard(_ mode: StyleModePreference) -> some View {
        Button {
            selectedMode = mode
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedMode == mode ? Theme.champagne : Theme.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(modeDescription(mode))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding()
            .background(selectedMode == mode ? Theme.cardFill : Theme.cardFill.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedMode == mode ? Theme.champagne : Theme.cardBorder, lineWidth: selectedMode == mode ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func directionCard(_ dir: StyleDirection) -> some View {
        Button {
            selectedDirection = dir
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selectedDirection == dir ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(selectedDirection == dir ? Theme.champagne : Theme.secondaryText)

                VStack(alignment: .leading, spacing: 3) {
                    Text(dir.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                    Text(dir.tagline)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selectedDirection == dir ? Theme.cardFill : Theme.cardFill.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedDirection == dir ? Theme.champagne : Theme.cardBorder, lineWidth: selectedDirection == dir ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func modeDescription(_ mode: StyleModePreference) -> String {
        switch mode {
        case .improve:
            "Steers every outfit toward polished, classic looks. Choose a style direction below."
        case .expand:
            "Reads your wardrobe and saved outfits to identify your personal style, then generates suggestions that feel authentically you. Gets better with more data."
        }
    }
}
