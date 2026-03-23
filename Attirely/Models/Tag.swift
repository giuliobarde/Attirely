import Foundation
import SwiftUI
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String
    var isPredefined: Bool
    var colorHex: String?
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Outfit.tags)
    var outfits: [Outfit] = []

    var tagColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return Theme.tagBackground
    }

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(name: String, isPredefined: Bool = false, colorHex: String? = nil) {
        self.name = Tag.normalized(name)
        self.isPredefined = isPredefined
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}
