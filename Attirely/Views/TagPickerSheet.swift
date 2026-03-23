import SwiftUI
import SwiftData

struct TagPickerSheet: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""
    @State private var isAddingTag = false

    var body: some View {
        NavigationStack {
            List {
                Section("Tags") {
                    ForEach(allTags) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            HStack {
                                TagChipView(tag: tag)
                                Spacer()
                                if isTagApplied(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.champagne)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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
                                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
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
        outfit.tags.contains { $0.persistentModelID == tag.persistentModelID }
    }

    private func toggleTag(_ tag: Tag) {
        if isTagApplied(tag) {
            outfit.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            outfit.tags.append(tag)
        }
        try? modelContext.save()
    }

    private func createAndApplyTag() {
        let normalized = Tag.normalized(newTagName)
        guard !normalized.isEmpty else { return }

        // If tag already exists, just apply it
        if let existing = allTags.first(where: { $0.name == normalized }) {
            if !isTagApplied(existing) {
                outfit.tags.append(existing)
            }
        } else {
            let tag = Tag(name: normalized, isPredefined: false)
            modelContext.insert(tag)
            outfit.tags.append(tag)
        }

        try? modelContext.save()
        newTagName = ""
        isAddingTag = false
    }
}
