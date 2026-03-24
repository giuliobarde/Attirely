import Foundation
import SwiftData

struct TagManager {

    static func createTag(name: String, scope: TagScope, context: ModelContext) {
        let normalized = Tag.normalized(name)
        guard !normalized.isEmpty else { return }
        guard !tagExists(name: normalized, scope: scope, context: context) else { return }
        let tag = Tag(name: normalized, isPredefined: false, scope: scope)
        context.insert(tag)
        try? context.save()
    }

    static func renameTag(_ tag: Tag, to newName: String, context: ModelContext) {
        guard !tag.isPredefined else { return }
        let normalized = Tag.normalized(newName)
        guard !normalized.isEmpty else { return }
        guard !tagExists(name: normalized, scope: tag.scope, context: context) else { return }
        tag.name = normalized
        try? context.save()
    }

    static func deleteTag(_ tag: Tag, context: ModelContext) {
        guard !tag.isPredefined else { return }
        context.delete(tag)
        try? context.save()
    }

    static func updateTagColor(_ tag: Tag, hex: String?, context: ModelContext) {
        tag.colorHex = hex
        try? context.save()
    }

    static func tagExists(name: String, scope: TagScope, context: ModelContext) -> Bool {
        let scopeStr = scope.rawValue
        let predicate = #Predicate<Tag> { $0.name == name && $0.scopeRaw == scopeStr }
        let count = (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
        return count > 0
    }

    static func resolveTags(from names: [String], allTags: [Tag], scope: TagScope) -> [Tag] {
        let scopedTags = allTags.filter { $0.scope == scope }
        let tagIndex = Dictionary(uniqueKeysWithValues: scopedTags.map { ($0.name, $0) })
        return names.compactMap { tagIndex[Tag.normalized($0)] }
    }
}
