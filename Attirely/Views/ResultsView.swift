import SwiftUI

struct ResultsView: View {
    let viewModel: ScanViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var duplicateReviewItem: ClothingItemDTO?
    @State private var editingItem: ClothingItemDTO?
    @State private var appearedItemIDs: Set<UUID> = []

    // Outfit editing state
    @State private var editOutfitName = ""
    @State private var editOutfitOccasion = ""
    @State private var outfitNameSynced = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                imageSection

                switch viewModel.scanProgress {
                case .idle:
                    EmptyView()

                case .analyzing, .checkingDuplicates, .error:
                    ScanProgressView(
                        progress: viewModel.scanProgress,
                        imageCount: viewModel.selectedImages.count,
                        onRetry: { viewModel.retry() }
                    )

                case .complete:
                    resultsSection
                }
            }
            .padding(.bottom)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.modelContext = modelContext
        }
        .onChange(of: viewModel.outfitSuggestion?.name) { _, newName in
            if !outfitNameSynced, let suggestion = viewModel.outfitSuggestion {
                editOutfitName = suggestion.name
                editOutfitOccasion = suggestion.occasion
                outfitNameSynced = true
            }
        }
        .sheet(item: $duplicateReviewItem) { dto in
            if let results = viewModel.duplicateResults[dto.id] {
                DuplicateReviewSheet(
                    scannedItem: dto,
                    duplicates: results,
                    onSaveAnyway: {
                        viewModel.saveItem(dto)
                    },
                    onSkip: {
                        viewModel.dismissItem(dto)
                    },
                    onUseExisting: { existingItem in
                        viewModel.useExistingItem(dtoID: dto.id, existingItem: existingItem)
                    }
                )
            }
        }
        .sheet(item: $editingItem) { dto in
            ScanItemEditSheet(dto: dto) { edited in
                viewModel.updateScannedItem(edited)
            }
        }
    }

    // MARK: - Image Section

    @ViewBuilder
    private var imageSection: some View {
        if viewModel.selectedImages.count == 1, let image = viewModel.selectedImages.first {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .padding(.horizontal)
        } else if viewModel.selectedImages.count > 1 {
            ImageThumbnailStrip(images: viewModel.selectedImages)
                .padding(.top, 4)
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Found \(viewModel.visibleItems.count) item\(viewModel.visibleItems.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)

                Spacer()
            }
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))

            // Save All button
            if viewModel.hasUnsavedItems {
                Button {
                    viewModel.saveAllItems()
                } label: {
                    Label("Save All to Wardrobe", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themePrimary)
                .padding(.horizontal)
            }

            // Outfit suggestion card
            if viewModel.isOutfitSaveEnabled {
                outfitSuggestionCard
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Item cards
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, dto in
                    VStack(spacing: 8) {
                        ClothingItemCard(
                            item: dto,
                            sourceImageIndices: viewModel.selectedImages.count > 1 ? dto.sourceImageIndices : nil,
                            totalImageCount: viewModel.selectedImages.count
                        )

                        // Duplicate warning (hide if already linked to existing)
                        if viewModel.existingItemMapping[dto.id] == nil,
                           let duplicates = viewModel.duplicateResults[dto.id] {
                            DuplicateWarningBanner(
                                results: duplicates,
                                onReview: { duplicateReviewItem = dto }
                            )
                        }

                        // Item status: linked / saved / actions
                        if viewModel.isItemLinked(dto) {
                            linkedItemBadge(for: dto)
                        } else if viewModel.isItemSaved(dto) {
                            savedBadge
                        } else {
                            itemActions(for: dto)
                        }
                    }
                    .opacity(appearedItemIDs.contains(dto.id) ? 1 : 0)
                    .offset(y: appearedItemIDs.contains(dto.id) ? 0 : 20)
                    .onAppear {
                        withAnimation(Animation.spring(duration: 0.4).delay(Double(index) * 0.05)) {
                            _ = appearedItemIDs.insert(dto.id)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Outfit Suggestion Card

    @ViewBuilder
    private var outfitSuggestionCard: some View {
        if viewModel.outfitSaved {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.champagne)
                Text("Outfit Saved")
                    .font(.subheadline)
                    .foregroundStyle(Theme.champagne)
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(Theme.champagne)
                    Text("Outfit Detected")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                }

                // Editable name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    TextField("Outfit name", text: $editOutfitName)
                        .font(.subheadline)
                        .padding(8)
                        .background(Theme.screenBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.cardBorder, lineWidth: 0.5)
                        )
                }

                // Editable occasion
                VStack(alignment: .leading, spacing: 4) {
                    Text("Occasion")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    TextField("Occasion", text: $editOutfitOccasion)
                        .font(.subheadline)
                        .padding(8)
                        .background(Theme.screenBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.cardBorder, lineWidth: 0.5)
                        )
                }

                // AI reasoning
                if let reasoning = viewModel.outfitSuggestion?.reasoning {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .italic()
                }

                // Composition warnings
                let warningItems = viewModel.visibleItems.compactMap { dto -> ClothingItem? in
                    viewModel.existingItemMapping[dto.id]
                }
                let warnings = OutfitLayerOrder.warnings(for: warningItems)
                if !warnings.isEmpty {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                // Missing footwear tip
                if case .validMissingFootwear = viewModel.outfitCompleteness {
                    HStack(spacing: 6) {
                        Image(systemName: "shoe.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.champagne)
                        Text("You can add footwear later")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                // Save as Outfit button
                Button {
                    viewModel.saveOutfit(name: editOutfitName, occasion: editOutfitOccasion)
                } label: {
                    Label("Save as Outfit", systemImage: "rectangle.stack.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themePrimary)
                .disabled(!viewModel.canSaveOutfit)
            }
            .themeCard()
        }
    }

    // MARK: - Item Actions

    private func itemActions(for dto: ClothingItemDTO) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.saveItem(dto)
            } label: {
                Label("Save", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themePrimary)

            Button {
                editingItem = dto
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themeSecondary)

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.dismissItem(dto)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(Theme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Linked Item Badge

    private func linkedItemBadge(for dto: ClothingItemDTO) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Theme.champagne)
            if let existing = viewModel.existingItemMapping[dto.id] {
                Text("Linked to \(existing.type)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.champagne)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.revertToNewItem(dtoID: dto.id)
                }
            } label: {
                Text("Undo")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Saved Badge

    private var savedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.champagne)
            Text("Saved to Wardrobe")
                .font(.subheadline)
                .foregroundStyle(Theme.champagne)
        }
        .transition(.scale.combined(with: .opacity))
    }
}
