import SwiftUI
import SwiftData

struct BulkTagEditSheet: View {
    let selectedOutfitIDs: Set<PersistentIdentifier>
    let allOutfits: [Outfit]
    let onApply: ([PersistentIdentifier: Bool]) -> Void

    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Environment(\.dismiss) private var dismiss

    @State private var tagStates: [PersistentIdentifier: TagState] = [:]

    private enum TagState {
        case checked, unchecked, mixed
    }

    var body: some View {
        NavigationStack {
            List(allTags) { tag in
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
        let selectedOutfits = allOutfits.filter { selectedOutfitIDs.contains($0.persistentModelID) }
        let totalSelected = selectedOutfits.count

        var computed: [PersistentIdentifier: TagState] = [:]
        for tag in allTags {
            let count = selectedOutfits.filter { outfit in
                outfit.tags.contains { $0.persistentModelID == tag.persistentModelID }
            }.count

            if count == totalSelected {
                computed[tag.persistentModelID] = .checked
            } else if count > 0 {
                computed[tag.persistentModelID] = .mixed
            } else {
                computed[tag.persistentModelID] = .unchecked
            }
        }
        tagStates = computed
        initialStates = computed
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
        for tag in allTags {
            let initial = initialStates[tag.persistentModelID, default: .unchecked]
            let current = tagStates[tag.persistentModelID, default: .unchecked]
            if !statesEqual(initial, current) {
                switch current {
                case .checked:
                    edits[tag.persistentModelID] = true
                case .unchecked:
                    edits[tag.persistentModelID] = false
                case .mixed:
                    break // unchanged mixed — shouldn't happen but skip
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
