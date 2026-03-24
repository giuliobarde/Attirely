import SwiftUI
import SwiftData

struct TagFilterBar: View {
    @Binding var selectedTagIDs: Set<PersistentIdentifier>
    let scope: TagScope
    var outfits: [Outfit] = []
    var items: [ClothingItem] = []
    @Query(sort: \Tag.name) private var allTags: [Tag]

    private var usedTags: [Tag] {
        let scopedTags = allTags.filter { $0.scope == scope }
        switch scope {
        case .outfit:
            return scopedTags.filter { tag in
                outfits.contains { outfit in
                    outfit.tags.contains { $0.persistentModelID == tag.persistentModelID }
                }
            }
        case .item:
            return scopedTags.filter { tag in
                items.contains { item in
                    item.tags.contains { $0.persistentModelID == tag.persistentModelID }
                }
            }
        }
    }

    var body: some View {
        if !usedTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation {
                            selectedTagIDs.removeAll()
                        }
                    } label: {
                        Text("All")
                            .themePill(isActive: selectedTagIDs.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(usedTags) { tag in
                        TagChipView(
                            tag: tag,
                            isSelected: selectedTagIDs.contains(tag.persistentModelID)
                        ) {
                            withAnimation {
                                if selectedTagIDs.contains(tag.persistentModelID) {
                                    selectedTagIDs.remove(tag.persistentModelID)
                                } else {
                                    selectedTagIDs.insert(tag.persistentModelID)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 6)
        }
    }
}
