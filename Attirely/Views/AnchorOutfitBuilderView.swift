import SwiftUI
import SwiftData

struct AnchorOutfitBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AnchorOutfitBuilderViewModel

    var weatherViewModel: WeatherViewModel?
    var userProfile: UserProfile?
    var styleSummaryText: String?

    @Query private var allItems: [ClothingItem]
    @Query private var allOutfits: [Outfit]

    @State private var outfitSaved = false

    init(
        anchorItem: ClothingItem,
        weatherViewModel: WeatherViewModel? = nil,
        userProfile: UserProfile? = nil,
        styleSummaryText: String? = nil
    ) {
        self.weatherViewModel = weatherViewModel
        self.userProfile = userProfile
        self.styleSummaryText = styleSummaryText
        self._viewModel = State(initialValue: AnchorOutfitBuilderViewModel(anchorItem: anchorItem))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    anchorItemCard
                    modeToggle
                    occasionPicker
                    generateButton

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if viewModel.hasResult {
                        resultSection
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.25), value: viewModel.hasResult)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Build an Outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isGenerating)
                }
            }
        }
    }

    // MARK: - Anchor Item Card

    private var anchorItemCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anchor Item")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.champagne)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 12) {
                anchorThumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.anchorItem.type)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.primaryText)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(ColorMapping.color(for: viewModel.anchorItem.primaryColor))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
                        Text(viewModel.anchorItem.primaryColor)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Text("\(viewModel.anchorItem.fabricEstimate) · \(viewModel.anchorItem.formality)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()
            }
            .themeCard()
        }
    }

    private var anchorThumbnail: some View {
        Group {
            let path = viewModel.anchorItem.imagePath ?? viewModel.anchorItem.sourceImagePath
            if let path, let image = ImageStorageService.loadImage(relativePath: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.placeholderFill)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Circle()
                            .fill(ColorMapping.color(for: viewModel.anchorItem.primaryColor))
                            .frame(width: 24, height: 24)
                    }
            }
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            Picker("Source", selection: $viewModel.useWardrobe) {
                Text("Use my wardrobe").tag(true)
                Text("Start fresh").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.useWardrobe) {
                viewModel.clearResult()
            }

            Text(viewModel.useWardrobe
                 ? "Claude fills the outfit from your wardrobe, with text suggestions for any gaps."
                 : "Claude describes a complete outfit around this item — no wardrobe items referenced.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Occasion Picker

    private var occasionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Occasion (Optional)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                Button("Any") { viewModel.selectedOccasionTier = nil }
                ForEach(OccasionTier.pickerGroups) { group in
                    Section(group.label) {
                        ForEach(group.items) { tier in
                            Button(tier.rawValue) {
                                viewModel.selectedOccasionTier = tier
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.selectedOccasionTier?.rawValue ?? "Any")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Group {
            if viewModel.isGenerating {
                HStack {
                    Spacer()
                    ProgressView("Building outfit…")
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                Button {
                    outfitSaved = false
                    viewModel.generate(
                        allItems: allItems,
                        userProfile: userProfile,
                        weatherContext: weatherViewModel?.weatherContextString,
                        styleSummary: styleSummaryText,
                        existingOutfits: Array(allOutfits)
                    )
                } label: {
                    HStack {
                        Spacer()
                        Label(viewModel.hasResult ? "Regenerate" : "Build Outfit", systemImage: "sparkles")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.themePrimary)
            }
        }
    }

    // MARK: - Result Section

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            if viewModel.useWardrobe, let suggestion = viewModel.wardrobeOutfitSuggestion {
                wardrobeResultSection(suggestion: suggestion)
            } else if !viewModel.useWardrobe, let fresh = viewModel.freshOutfit {
                freshResultSection(outfit: fresh)
            }
        }
    }

    // MARK: - Wardrobe Result

    private func wardrobeResultSection(suggestion: OutfitSuggestionDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            outfitHeader(name: suggestion.name, occasion: suggestion.occasion, reasoning: suggestion.reasoning)

            VStack(spacing: 10) {
                ForEach(OutfitLayerOrder.sorted(viewModel.matchedWardrobeItems)) { item in
                    wardrobeItemRow(item: item)
                }
            }

            if !viewModel.gapSuggestions.isEmpty {
                gapSuggestionsSection(gaps: viewModel.gapSuggestions)
            }

            if outfitSaved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Outfit saved")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                }
                .padding(.top, 4)
            } else {
                Button {
                    viewModel.saveOutfit(
                        modelContext: modelContext,
                        weatherSnapshot: weatherViewModel?.snapshot
                    )
                    outfitSaved = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Save Outfit", systemImage: "plus.circle")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.themePrimary)
            }
        }
    }

    private func wardrobeItemRow(item: ClothingItem) -> some View {
        HStack(spacing: 12) {
            let path = item.imagePath ?? item.sourceImagePath
            if let path, let image = ImageStorageService.loadImage(relativePath: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.placeholderFill)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Circle()
                            .fill(ColorMapping.color(for: item.primaryColor))
                            .frame(width: 20, height: 20)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if item.id == viewModel.anchorItem.id {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.champagne)
                    }
                    Text(item.type)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.primaryText)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(ColorMapping.color(for: item.primaryColor))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
                    Text(item.primaryColor)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(item.formality)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()
        }
        .padding(12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    private func gapSuggestionsSection(gaps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To complete this look")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.champagne)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(gaps, id: \.self) { gap in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bag")
                            .font(.caption)
                            .foregroundStyle(Theme.champagne)
                            .frame(width: 16)
                            .padding(.top, 2)
                        Text(gap)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(Theme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Fresh Result

    private func freshResultSection(outfit: AnchoredFreshOutfitDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            outfitHeader(name: outfit.name, occasion: outfit.occasion, reasoning: outfit.reasoning)

            VStack(alignment: .leading, spacing: 6) {
                Text("Anchor")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.champagne)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(spacing: 12) {
                    anchorThumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.anchorItem.type)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.primaryText)
                        Text(viewModel.anchorItem.primaryColor)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.cardBorder, lineWidth: 0.5)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Suggested Pieces")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.5)

                ForEach(outfit.suggestedItems.indices, id: \.self) { index in
                    suggestedItemCard(item: outfit.suggestedItems[index])
                }
            }
        }
    }

    private func suggestedItemCard(item: AnchoredFreshOutfitDTO.SuggestedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.category)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.pillActiveBg)
                .foregroundStyle(Theme.pillActiveText)
                .clipShape(Capsule())

            Text(item.colorAndFabric)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)

            Text(item.cutAndFit)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            Text(item.whyItWorks)
                .font(.caption)
                .italic()
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Shared Header

    private func outfitHeader(name: String, occasion: String, reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(occasion)
                    .font(.caption)
                    .foregroundStyle(Theme.champagne)
                    .fontWeight(.medium)
            }

            Text(reasoning)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
