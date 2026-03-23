import SwiftUI
import SwiftData

struct TagManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var viewModel = OutfitViewModel()
    @State private var newTagName = ""
    @State private var isAddingTag = false
    @State private var editingTag: Tag?
    @State private var editingName = ""

    private var predefinedTags: [Tag] { allTags.filter(\.isPredefined) }
    private var customTags: [Tag] { allTags.filter { !$0.isPredefined } }

    var body: some View {
        List {
            Section("Predefined Tags") {
                ForEach(predefinedTags) { tag in
                    HStack {
                        TagChipView(tag: tag)
                        Spacer()
                        Text("\(tag.outfits.count)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            Section("Custom Tags") {
                ForEach(customTags) { tag in
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

                            Text("\(tag.outfits.count)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)

                            ColorPicker("", selection: Binding(
                                get: { Color(hex: tag.colorHex ?? "") ?? Theme.champagne },
                                set: { color in
                                    viewModel.updateTagColor(tag, hex: color.toHex(), context: modelContext)
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
                    for index in offsets {
                        viewModel.deleteTag(customTags[index], context: modelContext)
                    }
                }

                if isAddingTag {
                    HStack {
                        TextField("New tag name", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .onSubmit { addTag() }
                        Button("Add") { addTag() }
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
        .navigationTitle("Manage Tags")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addTag() {
        viewModel.createTag(name: newTagName, context: modelContext)
        newTagName = ""
        isAddingTag = false
    }

    private func saveRename(_ tag: Tag) {
        viewModel.renameTag(tag, to: editingName, context: modelContext)
        editingTag = nil
        editingName = ""
    }
}
