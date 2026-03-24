import SwiftUI
import SwiftData

struct WardrobeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTagIDs: Set<PersistentIdentifier>
    @Binding var selectedFormalities: Set<String>
    @Binding var selectedColors: Set<String>
    let availableFormalities: [String]
    let availableColors: [String]
    let items: [ClothingItem]
    var onReset: () -> Void

    @Query(sort: \Tag.name) private var allTags: [Tag]

    private var usedItemTags: [Tag] {
        let scoped = allTags.filter { $0.scope == .item }
        return scoped.filter { tag in
            items.contains { item in
                item.tags.contains { $0.persistentModelID == tag.persistentModelID }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Tags
                    if !usedItemTags.isEmpty {
                        filterSection("Tags") {
                            FlowLayout(spacing: 8) {
                                ForEach(usedItemTags) { tag in
                                    TagChipView(
                                        tag: tag,
                                        isSelected: selectedTagIDs.contains(tag.persistentModelID)
                                    ) {
                                        if selectedTagIDs.contains(tag.persistentModelID) {
                                            selectedTagIDs.remove(tag.persistentModelID)
                                        } else {
                                            selectedTagIDs.insert(tag.persistentModelID)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Formality
                    if !availableFormalities.isEmpty {
                        filterSection("Formality") {
                            FlowLayout(spacing: 8) {
                                ForEach(availableFormalities, id: \.self) { formality in
                                    Button {
                                        if selectedFormalities.contains(formality) {
                                            selectedFormalities.remove(formality)
                                        } else {
                                            selectedFormalities.insert(formality)
                                        }
                                    } label: {
                                        Text(formality)
                                            .themePill(isActive: selectedFormalities.contains(formality))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Color
                    if !availableColors.isEmpty {
                        filterSection("Color") {
                            FlowLayout(spacing: 8) {
                                ForEach(availableColors, id: \.self) { color in
                                    Button {
                                        if selectedColors.contains(color) {
                                            selectedColors.remove(color)
                                        } else {
                                            selectedColors.insert(color)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(ColorMapping.color(for: color))
                                                .frame(width: 10, height: 10)
                                            Text(color)
                                        }
                                        .themePill(isActive: selectedColors.contains(color))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        onReset()
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.primaryText)

            content()
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
