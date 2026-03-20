import Foundation
import SwiftData

@Model
final class ScanSession {
    @Attribute(.unique) var id: UUID
    var imagePath: String
    var date: Date

    @Relationship(deleteRule: .nullify, inverse: \ClothingItem.scanSession)
    var items: [ClothingItem]

    init(imagePath: String, items: [ClothingItem] = [], date: Date = Date()) {
        self.id = UUID()
        self.imagePath = imagePath
        self.date = date
        self.items = items
    }
}
