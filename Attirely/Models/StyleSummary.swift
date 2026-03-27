import Foundation
import SwiftData

@Model
final class StyleSummary {
    @Attribute(.unique) var id: UUID

    var overallIdentity: String
    var styleModes: String?              // JSON-encoded [String]
    var temporalNotes: String?
    var gapObservations: String?
    var weatherBehavior: String?

    var behavioralNotes: String?          // JSON-encoded [AgentObservation]

    var lastAnalyzedAt: Date
    var itemCountAtLastAnalysis: Int
    var outfitCountAtLastAnalysis: Int
    var favoritedOutfitCountAtLastAnalysis: Int
    var analysisVersion: Int

    var isUserEdited: Bool
    var isAIEnriched: Bool

    var createdAt: Date

    var styleModesDecoded: [StyleModeDTO] {
        get {
            guard let data = styleModes?.data(using: .utf8),
                  let array = try? JSONDecoder().decode([StyleModeDTO].self, from: data)
            else { return [] }
            return array
        }
        set {
            styleModes = String(data: (try? JSONEncoder().encode(newValue)) ?? Data(), encoding: .utf8) ?? "[]"
        }
    }

    var behavioralNotesDecoded: [AgentObservation] {
        get {
            guard let data = behavioralNotes?.data(using: .utf8),
                  let array = try? JSONDecoder().decode([AgentObservation].self, from: data)
            else { return [] }
            return array
        }
        set {
            behavioralNotes = String(data: (try? JSONEncoder().encode(newValue)) ?? Data(), encoding: .utf8) ?? "[]"
        }
    }

    /// Active, non-stale observations sorted by most recent.
    var activeObservations: [AgentObservation] {
        behavioralNotesDecoded
            .filter { $0.isActive && !$0.isStale }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    init(
        overallIdentity: String,
        itemCountAtLastAnalysis: Int = 0,
        outfitCountAtLastAnalysis: Int = 0,
        favoritedOutfitCountAtLastAnalysis: Int = 0
    ) {
        self.id = UUID()
        self.overallIdentity = overallIdentity
        self.lastAnalyzedAt = Date()
        self.itemCountAtLastAnalysis = itemCountAtLastAnalysis
        self.outfitCountAtLastAnalysis = outfitCountAtLastAnalysis
        self.favoritedOutfitCountAtLastAnalysis = favoritedOutfitCountAtLastAnalysis
        self.analysisVersion = 1
        self.isUserEdited = false
        self.isAIEnriched = false
        self.createdAt = Date()
    }
}
