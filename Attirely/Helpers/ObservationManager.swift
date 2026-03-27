import Foundation

enum ObservationManager {

    // MARK: - Record / Reinforce

    /// Record a new observation or reinforce an existing match. Returns the updated array.
    static func recordObservation(
        pattern: String,
        category: ObservationCategory,
        signal: ObservationSignal,
        threshold: Int,
        occasionContext: String?,
        in observations: [AgentObservation]
    ) -> [AgentObservation] {
        var updated = observations

        if let index = findMatch(pattern: pattern, category: category, in: updated) {
            updated[index].occurrenceCount += 1
            updated[index].lastSeen = Date()
            updated[index].sourceConversations += 1
        } else {
            var observation = AgentObservation(
                pattern: pattern,
                category: category,
                signal: signal,
                threshold: threshold,
                occasionContext: occasionContext
            )
            observation.sourceConversations = 1
            updated.append(observation)
        }

        return updated
    }

    // MARK: - Fuzzy Matching

    /// Find an existing observation matching by category and word overlap.
    static func findMatch(
        pattern: String,
        category: ObservationCategory,
        in observations: [AgentObservation]
    ) -> Int? {
        let patternWords = normalizedWords(pattern)
        guard !patternWords.isEmpty else { return nil }

        var bestIndex: Int?
        var bestScore: Double = 0

        for (index, observation) in observations.enumerated() {
            guard observation.category == category else { continue }

            let existingWords = normalizedWords(observation.pattern)
            guard !existingWords.isEmpty else { continue }

            let intersection = patternWords.intersection(existingWords)
            let union = patternWords.union(existingWords)
            let score = Double(intersection.count) / Double(union.count)

            // Require at least 40% word overlap (Jaccard similarity)
            if score > 0.4 && score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    // MARK: - Classification

    /// Classify an insight into category and signal. Uses Claude-provided values if available,
    /// otherwise infers from text keywords.
    static func classifyInsight(
        _ text: String,
        category: String?,
        signal: String?
    ) -> (ObservationCategory, ObservationSignal) {
        let resolvedSignal: ObservationSignal
        if let signal, let parsed = ObservationSignal(rawValue: signal) {
            resolvedSignal = parsed
        } else {
            resolvedSignal = inferSignal(from: text)
        }

        let resolvedCategory: ObservationCategory
        if let category, let parsed = ObservationCategory(rawValue: category) {
            resolvedCategory = parsed
        } else {
            resolvedCategory = inferCategory(from: text, signal: resolvedSignal)
        }

        return (resolvedCategory, resolvedSignal)
    }

    /// Infer a negative signal from an editOutfit item removal.
    static func inferNegativeSignal(
        removedItem: ClothingItem,
        occasionContext: String?
    ) -> (pattern: String, category: ObservationCategory)? {
        let type = removedItem.type
        let color = removedItem.primaryColor

        if let occasion = occasionContext, !occasion.isEmpty {
            return (
                pattern: "Dislikes \(type.lowercased()) for \(occasion.lowercased()) occasions",
                category: .itemAversion
            )
        } else {
            return (
                pattern: "Removed \(color.lowercased()) \(type.lowercased()) from outfit",
                category: .itemAversion
            )
        }
    }

    // MARK: - Pruning

    /// Remove stale observations and cap total count.
    static func prune(_ observations: [AgentObservation]) -> [AgentObservation] {
        let maxObservations = 30

        var filtered = observations.filter { !$0.isStale || $0.isResolved }

        if filtered.count > maxObservations {
            // Keep resolved + most recent active
            filtered.sort { $0.lastSeen > $1.lastSeen }
            let resolved = filtered.filter(\.isResolved)
            let active = filtered.filter { !$0.isResolved }
            let keepActive = Array(active.prefix(maxObservations - resolved.count))
            filtered = resolved + keepActive
        }

        return filtered
    }

    // MARK: - Prompt String

    /// Format active observations for system prompt injection.
    static func promptString(
        from observations: [AgentObservation],
        maxCount: Int = 15,
        forOccasion: OccasionTier? = nil
    ) -> String? {
        var candidates = observations.filter { $0.isActive && !$0.isStale }
        guard !candidates.isEmpty else { return nil }

        // Prioritize occasion-relevant observations
        if let occasion = forOccasion {
            let occasionName = occasion.rawValue.lowercased()
            candidates.sort { a, b in
                let aRelevant = a.occasionContext?.lowercased().contains(occasionName) ?? false
                let bRelevant = b.occasionContext?.lowercased().contains(occasionName) ?? false
                if aRelevant != bRelevant { return aRelevant }
                return a.occurrenceCount > b.occurrenceCount
            }
        } else {
            candidates.sort { $0.occurrenceCount > $1.occurrenceCount }
        }

        let selected = candidates.prefix(maxCount)
        let lines = selected.map { observation -> String in
            var line = "- \(observation.pattern)"
            if observation.occurrenceCount > 1 {
                line += " (observed \(observation.occurrenceCount) times)"
            } else {
                line += " (explicitly stated)"
            }
            return line
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private static func normalizedWords(_ text: String) -> Set<String> {
        let stopWords: Set<String> = ["the", "a", "an", "for", "to", "in", "of", "with", "and", "or", "is", "are", "was", "from"]
        return Set(
            text.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 1 && !stopWords.contains($0) }
        )
    }

    private static func inferSignal(from text: String) -> ObservationSignal {
        let negativeKeywords = ["hate", "dislike", "avoid", "never", "don't like", "not a fan", "remove", "no more", "stop"]
        let lowered = text.lowercased()
        for keyword in negativeKeywords {
            if lowered.contains(keyword) { return .negative }
        }
        return .positive
    }

    private static func inferCategory(from text: String, signal: ObservationSignal) -> ObservationCategory {
        let lowered = text.lowercased()

        let colorWords = ["color", "colour", "red", "blue", "green", "black", "white", "brown", "navy",
                          "beige", "cream", "grey", "gray", "pink", "purple", "yellow", "orange",
                          "burgundy", "maroon", "teal", "olive", "tan", "charcoal", "ivory"]
        let fabricWords = ["fabric", "material", "cotton", "wool", "linen", "silk", "denim",
                           "leather", "suede", "polyester", "fleece", "knit", "cashmere", "satin"]
        let formalityWords = ["formal", "casual", "dressy", "relaxed", "dressed up", "dressed down",
                              "business", "smart casual", "polished", "structured"]
        let occasionWords = ["occasion", "event", "work", "office", "weekend", "date", "party",
                             "dinner", "meeting", "gym", "outdoor"]

        for word in colorWords where lowered.contains(word) {
            return signal == .negative ? .colorAversion : .colorPreference
        }
        for word in fabricWords where lowered.contains(word) {
            return signal == .negative ? .fabricAversion : .fabricPreference
        }
        for word in formalityWords where lowered.contains(word) {
            return .formalityPreference
        }
        for word in occasionWords where lowered.contains(word) {
            return .occasionBehavior
        }

        // Check for specific item references
        let itemWords = ["shoe", "boot", "sneaker", "heel", "sandal", "blazer", "jacket",
                         "jean", "trouser", "shirt", "dress", "skirt", "coat", "hat", "watch", "tie"]
        for word in itemWords where lowered.contains(word) {
            return signal == .negative ? .itemAversion : .itemPreference
        }

        return .generalStyle
    }
}
