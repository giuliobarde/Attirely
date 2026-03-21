import SwiftUI

struct DuplicateReviewSheet: View {
    let scannedItem: ClothingItemDTO
    let duplicates: [DuplicateResult]
    let onSaveAnyway: () -> Void
    let onSkip: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Scanned item summary
                    VStack(spacing: 8) {
                        Text("Scanned Item")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(ColorMapping.color(for: scannedItem.primaryColor))
                                .frame(width: 20, height: 20)
                            Text(scannedItem.type)
                                .font(.subheadline.weight(.medium))
                            Text("— \(scannedItem.primaryColor) \(scannedItem.pattern)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(scannedItem.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Matches
                    Text("Potential Matches")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(duplicates.enumerated()), id: \.offset) { _, result in
                        DuplicateMatchCard(result: result)
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            onSaveAnyway()
                            dismiss()
                        } label: {
                            Label("Save Anyway", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onSkip()
                            dismiss()
                        } label: {
                            Label("Skip This Item", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Duplicate Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DuplicateMatchCard: View {
    let result: DuplicateResult

    private var classificationLabel: String {
        switch result.classification {
        case .sameItem: return "Likely same item"
        case .similar: return "Similar but different"
        case .noMatch: return "No match"
        }
    }

    private var classificationColor: Color {
        switch result.classification {
        case .sameItem: return .orange
        case .similar: return .blue
        case .noMatch: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.existingItem.type)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(classificationLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(classificationColor.opacity(0.15))
                    .foregroundStyle(classificationColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(ColorMapping.color(for: result.existingItem.primaryColor))
                    .frame(width: 14, height: 14)
                Text("\(result.existingItem.primaryColor) \(result.existingItem.pattern)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(result.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
