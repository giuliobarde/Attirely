import Foundation

// MARK: - Observation Category

enum ObservationCategory: String, Codable, CaseIterable {
    case formalityPreference
    case colorAversion
    case colorPreference
    case fabricPreference
    case fabricAversion
    case occasionBehavior
    case itemPreference
    case itemAversion
    case generalStyle

    /// Low-impact observations can be auto-graduated without user confirmation.
    var isLowImpact: Bool {
        switch self {
        case .colorPreference, .colorAversion, .fabricPreference, .fabricAversion:
            true
        case .formalityPreference, .occasionBehavior, .itemPreference, .itemAversion, .generalStyle:
            false
        }
    }
}

// MARK: - Observation Signal

enum ObservationSignal: String, Codable {
    case positive
    case negative
}

// MARK: - Agent Observation

struct AgentObservation: Codable, Identifiable {
    let id: UUID
    var pattern: String
    var category: ObservationCategory
    var signal: ObservationSignal
    var occurrenceCount: Int
    var firstSeen: Date
    var lastSeen: Date
    var threshold: Int
    var isResolved: Bool
    var occasionContext: String?
    var sourceConversations: Int

    enum CodingKeys: String, CodingKey {
        case id, pattern, category, signal, threshold
        case occurrenceCount = "occurrence_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case isResolved = "is_resolved"
        case occasionContext = "occasion_context"
        case sourceConversations = "source_conversations"
    }

    /// Whether the observation has enough occurrences to be considered active.
    var isActive: Bool {
        occurrenceCount >= threshold && !isResolved
    }

    /// Observations older than 90 days without reinforcement are stale.
    var isStale: Bool {
        Date().timeIntervalSince(lastSeen) > 90 * 24 * 60 * 60
    }

    init(
        pattern: String,
        category: ObservationCategory,
        signal: ObservationSignal,
        threshold: Int = 3,
        occasionContext: String? = nil
    ) {
        self.id = UUID()
        self.pattern = pattern
        self.category = category
        self.signal = signal
        self.occurrenceCount = 1
        self.firstSeen = Date()
        self.lastSeen = Date()
        self.threshold = threshold
        self.isResolved = false
        self.occasionContext = occasionContext
        self.sourceConversations = 1
    }
}
