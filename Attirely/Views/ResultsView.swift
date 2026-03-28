import SwiftUI

struct ResultsView: View {
    let viewModel: ScanViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var duplicateReviewItem: ClothingItemDTO?
    @State private var editingItem: ClothingItemDTO?
    @State private var appearedItemIDs: Set<UUID> = []

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

            // Item cards
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, dto in
                    VStack(spacing: 8) {
                        ClothingItemCard(
                            item: dto,
                            sourceImageIndices: viewModel.selectedImages.count > 1 ? dto.sourceImageIndices : nil,
                            totalImageCount: viewModel.selectedImages.count
                        )

                        // Duplicate warning
                        if let duplicates = viewModel.duplicateResults[dto.id] {
                            DuplicateWarningBanner(
                                results: duplicates,
                                onReview: { duplicateReviewItem = dto }
                            )
                        }

                        // Save/dismiss controls
                        if viewModel.isItemSaved(dto) {
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
