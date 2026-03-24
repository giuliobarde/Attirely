import SwiftUI
import SwiftData

struct TagPickerSheet: View {
    @Binding var selectedTags: [Tag]
    let scope: TagScope
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""
    @State private var isAddingTag = false

    private var scopedTags: [Tag] {
        allTags.filter { $0.scope == scope }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Tags") {
                    ForEach(scopedTags) { tag in
                        HStack {
                            TagChipView(tag: tag)
                            Spacer()
                            if isTagApplied(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.champagne)
                                    .font(.subheadline)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggleTag(tag) }
                    }
                }

                Section {
                    if isAddingTag {
                        HStack {
                            TextField("Tag name", text: $newTagName)
                                .textFieldStyle(.plain)
                                .onSubmit { createAndApplyTag() }
                            Button("Add") { createAndApplyTag() }
                                .foregroundStyle(Theme.champagne)
                                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            isAddingTag = true
                        } label: {
                            Label("New Tag", systemImage: "plus")
                                .foregroundStyle(Theme.champagne)
                        }
                    }
                }
            }
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.champagne)
                }
            }
        }
    }

    private func isTagApplied(_ tag: Tag) -> Bool {
        selectedTags.contains { $0.persistentModelID == tag.persistentModelID }
    }

    private func toggleTag(_ tag: Tag) {
        var next = selectedTags
        if let index = next.firstIndex(where: { $0.persistentModelID == tag.persistentModelID }) {
            next.remove(at: index)
        } else {
            next.append(tag)
        }
        selectedTags = next
    }

    private func createAndApplyTag() {
        let normalized = Tag.normalized(newTagName)
        guard !normalized.isEmpty else { return }

        if let existing = scopedTags.first(where: { $0.name == normalized }) {
            var next = selectedTags
            if !next.contains(where: { $0.persistentModelID == existing.persistentModelID }) {
                next.append(existing)
                selectedTags = next
            }
        } else {
            let tag = Tag(name: normalized, isPredefined: false, scope: scope)
            modelContext.insert(tag)
            var next = selectedTags
            next.append(tag)
            selectedTags = next
            try? modelContext.save()
        }

        newTagName = ""
        isAddingTag = false
    }
}
