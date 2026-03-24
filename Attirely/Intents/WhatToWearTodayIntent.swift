import AppIntents
import SwiftData

struct WhatToWearTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What should I wear today?"
    static let description: IntentDescription = "Get an outfit suggestion based on today's weather and your style."
    static let openAppWhenRun = false

    @Dependency
    private var modelContainer: ModelContainer

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(modelContainer)
        do {
            let result = try await SiriOutfitService.selectOutfit(occasion: nil, context: context)
            return .result(dialog: "\(result.spokenSummary)")
        } catch let error as SiriOutfitError {
            return .result(dialog: "\(error.localizedDescription)")
        } catch {
            return .result(dialog: "Something went wrong. Try again in a moment.")
        }
    }
}
