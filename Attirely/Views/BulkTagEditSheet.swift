import SwiftUI
import SwiftData

struct BulkTagEditSheet: View {
    let scope: TagScope
    var selectedOutfitIDs: Set<PersistentIdentifier> = []
    var allOutfits: [Outfit] = []
    var selectedItemIDs: Set<PersistentIdentifier> = []
    var allItems: [ClothingItem] = []
    let onApply: ([PersistentIdentifier: Bool]) -> Void

    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Environment(\.dismiss) private var dismiss

    @State private var tagStates: [PersistentIdentifier: TagState] = [:]

    private enum TagState {
        case checked, unchecked, mixed
    }

    private var scopedTags: [Tag] {
        allTags.filter { $0.scope == scope }
    }

    var body: some View {
        NavigationStack {
            List(scopedTags) { tag in
                HStack {
                    TagChipView(tag: tag)
                    Spacer()
                    stateIndicator(for: tag)
                }
                .contentShape(Rectangle())
                .onTapGesture { cycleState(for: tag) }
                .listRowBackground(Theme.cardFill)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        onApply(buildEdits())
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.champagne)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { computeInitialStates() }
    }

    // MARK: - State Indicator

    @ViewBuilder
    private func stateIndicator(for tag: Tag) -> some View {
        switch tagStates[tag.persistentModelID, default: .unchecked] {
        case .checked:
            Image(systemName: "checkmark")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.champagne)
        case .mixed:
            Text("Mixed")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        case .unchecked:
            EmptyView()
        }
    }

    // MARK: - State Logic

    private func computeInitialStates() {
        var computed: [PersistentIdentifier: TagState] = [:]

        switch scope {
        case .outfit:
            let targets = allOutfits.filter { selectedOutfitIDs.contains($0.persistentModelID) }
            let total = targets.count
            for tag in scopedTags {
                let count = targets.filter { outfit in
                    outfit.tags.contains { $0.persistentModelID == tag.persistentModelID }
                }.count
                computed[tag.persistentModelID] = stateFor(count: count, total: total)
            }
        case .item:
            let targets = allItems.filter { selectedItemIDs.contains($0.persistentModelID) }
            let total = targets.count
            for tag in scopedTags {
                let count = targets.filter { item in
                    item.tags.contains { $0.persistentModelID == tag.persistentModelID }
                }.count
                computed[tag.persistentModelID] = stateFor(count: count, total: total)
            }
        }

        tagStates = computed
        initialStates = computed
    }

    private func stateFor(count: Int, total: Int) -> TagState {
        if count == total { .checked }
        else if count > 0 { .mixed }
        else { .unchecked }
    }

    private func cycleState(for tag: Tag) {
        let current = tagStates[tag.persistentModelID, default: .unchecked]
        switch current {
        case .mixed:
            tagStates[tag.persistentModelID] = .unchecked
        case .unchecked:
            tagStates[tag.persistentModelID] = .checked
        case .checked:
            tagStates[tag.persistentModelID] = .unchecked
        }
    }

    // MARK: - Build Edits

    @State private var initialStates: [PersistentIdentifier: TagState] = [:]

    private func buildEdits() -> [PersistentIdentifier: Bool] {
        var edits: [PersistentIdentifier: Bool] = [:]
        for tag in scopedTags {
            let initial = initialStates[tag.persistentModelID, default: .unchecked]
            let current = tagStates[tag.persistentModelID, default: .unchecked]
            if !statesEqual(initial, current) {
                switch current {
                case .checked:
                    edits[tag.persistentModelID] = true
                case .unchecked:
                    edits[tag.persistentModelID] = false
                case .mixed:
                    break
                }
            }
        }
        return edits
    }

    private func statesEqual(_ a: TagState, _ b: TagState) -> Bool {
        switch (a, b) {
        case (.checked, .checked), (.unchecked, .unchecked), (.mixed, .mixed):
            return true
        default:
            return false
        }
    }
}
