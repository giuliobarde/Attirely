import AppIntents
import SwiftData

enum OutfitOccasion: String, AppEnum {
    case casual = "casual"
    case dateNight = "date night"
    case work = "work"
    case formal = "formal"
    case gym = "gym"
    case travel = "travel"
    case outdoor = "outdoor"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Occasion")

    static let caseDisplayRepresentations: [OutfitOccasion: DisplayRepresentation] = [
        .casual: "Casual",
        .dateNight: "Date Night",
        .work: "Work",
        .formal: "Formal",
        .gym: "Gym",
        .travel: "Travel",
        .outdoor: "Outdoor"
    ]
}

struct WhatToWearToIntent: AppIntent {
    static let title: LocalizedStringResource = "What should I wear to an event?"
    static let description: IntentDescription = "Get an outfit suggestion for a specific occasion."
    static let openAppWhenRun = false

    @Parameter(title: "Occasion")
    var occasion: OutfitOccasion

    @Dependency
    private var modelContainer: ModelContainer

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(modelContainer)
        do {
            let result = try await SiriOutfitService.selectOutfit(occasion: occasion.rawValue, context: context)
            return .result(dialog: "\(result.spokenSummary)")
        } catch let error as SiriOutfitError {
            return .result(dialog: "\(error.localizedDescription)")
        } catch {
            return .result(dialog: "Something went wrong. Try again in a moment.")
        }
    }
}
