import SwiftUI
import SwiftData

struct AnchorOutfitBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AnchorOutfitBuilderViewModel
    @State private var expandedIndices: Set<Int> = []

    var weatherViewModel: WeatherViewModel?
    var userProfile: UserProfile?
    var styleSummaryText: String?

    @Query private var allItems: [ClothingItem]
    @Query private var allOutfits: [Outfit]

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
                    }

                    if viewModel.hasResult {
                        outfitCardsSection
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: viewModel.hasResult)
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
                expandedIndices = []
            }

            Text(viewModel.useWardrobe
                 ? "Claude fills outfits from your wardrobe, with text suggestions for any gaps."
                 : "Claude describes complete outfits around this item — no wardrobe items referenced.")
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
                    ProgressView("Building outfits…")
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                Button {
                    expandedIndices = []
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
                        Label(viewModel.hasResult ? "Regenerate" : "Build Outfits", systemImage: "sparkles")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.themePrimary)
            }
        }
    }

    // MARK: - Outfit Cards

    private var outfitCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            ForEach(viewModel.generatedOutfits.indices, id: \.self) { index in
                outfitCard(outfit: viewModel.generatedOutfits[index], index: index)
            }
        }
    }

    private func outfitCard(outfit: AnchorOutfitResultDTO, index: Int) -> some View {
        let isExpanded = expandedIndices.contains(index)

        return VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedIndices.remove(index)
                    } else {
                        expandedIndices.insert(index)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(outfit.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.primaryText)
                            .multilineTextAlignment(.leading)

                        Text(outfit.occasion)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.pillActiveBg)
                            .foregroundStyle(Theme.pillActiveText)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal)

                    // Items
                    VStack(spacing: 8) {
                        ForEach(outfit.items.indices, id: \.self) { i in
                            outfitItemRow(
                                item: outfit.items[i],
                                isAnchor: outfit.items[i].wardrobeItemId == viewModel.anchorItem.id.uuidString,
                                candidates: viewModel.wardrobeCandidates
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Styling note
                    if let note = outfit.stylingNote, !note.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(Theme.champagne)
                                .padding(.top, 1)
                            Text(note)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal)
                    }

                    // Save button (wardrobe mode only)
                    if viewModel.canSave(outfit) {
                        if viewModel.savedIndices.contains(index) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Outfit saved")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.primaryText)
                            }
                            .padding(.horizontal)
                        } else {
                            Button {
                                viewModel.saveOutfit(
                                    at: index,
                                    modelContext: modelContext,
                                    weatherSnapshot: weatherViewModel?.snapshot
                                )
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Save Outfit", systemImage: "plus.circle")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.themePrimary)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: Theme.obsidian.opacity(0.05), radius: 4, y: 2)
    }

    private func outfitItemRow(
        item: AnchorOutfitResultDTO.Item,
        isAnchor: Bool,
        candidates: [ClothingItem]
    ) -> some View {
        let wardrobeItem = item.source == "wardrobe"
            ? candidates.first(where: { $0.id.uuidString == item.wardrobeItemId })
            : nil

        return HStack(spacing: 12) {
            // Thumbnail or category icon
            if let wi = wardrobeItem {
                let path = wi.imagePath ?? wi.sourceImagePath
                if let path, let image = ImageStorageService.loadImage(relativePath: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.placeholderFill)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Circle()
                                .fill(ColorMapping.color(for: wi.primaryColor))
                                .frame(width: 18, height: 18)
                        }
                }
            } else {
                // Suggested item — category placeholder
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.pillDefaultBg)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: categorySymbol(for: item.category))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if isAnchor {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.champagne)
                    }
                    Text(item.description)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                }

                Text(item.whyItWorks)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Source badge
            if item.source == "suggested" {
                Text("Shop")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.champagne.opacity(0.15))
                    .foregroundStyle(Theme.champagne)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func categorySymbol(for category: String) -> String {
        switch category {
        case "Top":        return "tshirt"
        case "Bottom":     return "rectangle.portrait"
        case "Outerwear":  return "cloud.drizzle"
        case "Footwear":   return "shoe"
        case "Accessory":  return "sparkle"
        case "Full Body":  return "person"
        default:           return "hanger"
        }
    }
}
