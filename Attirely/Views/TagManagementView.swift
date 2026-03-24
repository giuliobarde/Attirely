import SwiftUI
import SwiftData

struct TagManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""
    @State private var addingScope: TagScope?
    @State private var editingTag: Tag?
    @State private var editingName = ""

    private func predefinedTags(for scope: TagScope) -> [Tag] {
        allTags.filter { $0.scope == scope && $0.isPredefined }
    }

    private func customTags(for scope: TagScope) -> [Tag] {
        allTags.filter { $0.scope == scope && !$0.isPredefined }
    }

    var body: some View {
        List {
            tagScopeSection(scope: .outfit, title: "Outfit Tags")
            tagScopeSection(scope: .item, title: "Item Tags")
        }
        .navigationTitle("Manage Tags")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Scope Section

    @ViewBuilder
    private func tagScopeSection(scope: TagScope, title: String) -> some View {
        let predefined = predefinedTags(for: scope)
        let custom = customTags(for: scope)

        Section("\(title) — Predefined") {
            ForEach(predefined) { tag in
                HStack {
                    TagChipView(tag: tag)
                    Spacer()
                    Text("\(usageCount(for: tag))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }

        Section("\(title) — Custom") {
            ForEach(custom) { tag in
                HStack {
                    if editingTag?.persistentModelID == tag.persistentModelID {
                        TextField("Tag name", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .onSubmit { saveRename(tag) }

                        Button {
                            saveRename(tag)
                        } label: {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.champagne)
                        }
                        .buttonStyle(.plain)
                    } else {
                        TagChipView(tag: tag)

                        Spacer()

                        Text("\(usageCount(for: tag))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)

                        ColorPicker("", selection: Binding(
                            get: {
                                if let h = tag.colorHex, let c = Color(hex: h) { return c }
                                return Color(hex: Tag.derivedAccentHex(from: tag.name)) ?? Theme.champagne
                            },
                            set: { color in
                                TagManager.updateTagColor(tag, hex: color.toHex(), context: modelContext)
                            }
                        ))
                        .labelsHidden()
                        .frame(width: 28, height: 28)

                        Button {
                            editingName = tag.name
                            editingTag = tag
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onDelete { offsets in
                let tags = custom
                for index in offsets {
                    TagManager.deleteTag(tags[index], context: modelContext)
                }
            }

            if addingScope == scope {
                HStack {
                    TextField("New tag name", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit { addTag(scope: scope) }
                    Button("Add") { addTag(scope: scope) }
                        .foregroundStyle(Theme.champagne)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    addingScope = scope
                } label: {
                    Label("New Tag", systemImage: "plus")
                        .foregroundStyle(Theme.champagne)
                }
            }
        }
    }

    // MARK: - Helpers

    private func usageCount(for tag: Tag) -> Int {
        switch tag.scope {
        case .outfit: tag.outfits.count
        case .item: tag.items.count
        }
    }

    private func addTag(scope: TagScope) {
        TagManager.createTag(name: newTagName, scope: scope, context: modelContext)
        newTagName = ""
        addingScope = nil
    }

    private func saveRename(_ tag: Tag) {
        TagManager.renameTag(tag, to: editingName, context: modelContext)
        editingTag = nil
        editingName = ""
    }
}
