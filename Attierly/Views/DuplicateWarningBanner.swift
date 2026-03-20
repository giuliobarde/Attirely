import SwiftUI

struct DuplicateWarningBanner: View {
    let results: [DuplicateResult]
    let onReview: () -> Void

    private var hasSameItem: Bool {
        results.contains { $0.classification == .sameItem }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hasSameItem ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(hasSameItem ? .orange : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasSameItem
                    ? "This item may already be in your wardrobe"
                    : "Similar items found in your wardrobe")
                    .font(.caption)
                    .fontWeight(.medium)

                Text("\(results.count) potential match\(results.count == 1 ? "" : "es")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Review") {
                onReview()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(hasSameItem ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
