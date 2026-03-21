import SwiftUI

struct ResultsView: View {
    let viewModel: ScanViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var duplicateReviewItem: ClothingItemDTO?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing your clothes...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            viewModel.retry()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                    .padding(.horizontal)
                } else if !viewModel.visibleItems.isEmpty {
                    // Save All button
                    if viewModel.hasUnsavedItems {
                        Button {
                            viewModel.saveAllItems()
                        } label: {
                            Label("Save All to Wardrobe", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }

                    if viewModel.isCheckingDuplicates {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking for duplicates...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Item cards with save/dismiss controls
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.visibleItems) { dto in
                            VStack(spacing: 8) {
                                ClothingItemCard(item: dto)

                                // Duplicate warning
                                if let duplicates = viewModel.duplicateResults[dto.id] {
                                    DuplicateWarningBanner(
                                        results: duplicates,
                                        onReview: { duplicateReviewItem = dto }
                                    )
                                }

                                // Save/dismiss controls
                                if viewModel.isItemSaved(dto) {
                                    Label("Saved to Wardrobe", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.green)
                                } else {
                                    HStack(spacing: 12) {
                                        Button {
                                            viewModel.saveItem(dto)
                                        } label: {
                                            Label("Save", systemImage: "plus.circle")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button {
                                            viewModel.dismissItem(dto)
                                        } label: {
                                            Label("Dismiss", systemImage: "xmark")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
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
    }
}
