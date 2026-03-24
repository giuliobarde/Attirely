import AppIntents

struct AttirelyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatToWearTodayIntent(),
            phrases: [
                "What should I wear today with \(.applicationName)",
                "Suggest an outfit with \(.applicationName)",
                "What do I wear today \(.applicationName)"
            ],
            shortTitle: "Today's Outfit",
            systemImageName: "tshirt"
        )
        AppShortcut(
            intent: WhatToWearToIntent(),
            phrases: [
                "What should I wear to \(\.$occasion) with \(.applicationName)",
                "Outfit for \(\.$occasion) with \(.applicationName)",
                "Suggest something for \(\.$occasion) \(.applicationName)"
            ],
            shortTitle: "Outfit for Occasion",
            systemImageName: "sparkles"
        )
    }
}
