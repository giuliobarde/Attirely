import Foundation

// Pure item/outfit resolution helpers. Two addressing modes:
// 1. Alias (preferred) — 6-hex prefix of the UUID, exposed to the agent via tool results.
// 2. Description fallback — fuzzy word-overlap scoring on type/color/category/fabric/pattern.
//
// matchItem routes through resolveAlias first so a leaked full UUID or alias token in a
// description ("use a3f91c wool coat") still resolves deterministically.

enum OutfitMatcher {

    // MARK: - Aliases

    static let aliasLength = 6

    static func alias(for item: ClothingItem) -> String {
        aliasPrefix(from: item.id)
    }

    static func alias(for outfit: Outfit) -> String {
        aliasPrefix(from: outfit.id)
    }

    private static func aliasPrefix(from uuid: UUID) -> String {
        String(uuid.uuidString.lowercased().prefix(aliasLength))
    }

    // Resolve a single token to an item. Returns nil if the token doesn't parse as a
    // full UUID, isn't a unique alias prefix, or doesn't correspond to any candidate.
    static func resolveAlias(_ token: String, in items: [ClothingItem]) -> ClothingItem? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        if cleaned.count == 36, let uuid = UUID(uuidString: cleaned) {
            return items.first { $0.id == uuid }
        }

        if isHex(cleaned), cleaned.count >= 4, cleaned.count <= 8 {
            let matches = items.filter { $0.id.uuidString.lowercased().hasPrefix(cleaned) }
            return matches.count == 1 ? matches.first : nil
        }

        return nil
    }

    static func resolveAlias(_ token: String, in outfits: [Outfit]) -> Outfit? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        if cleaned.count == 36, let uuid = UUID(uuidString: cleaned) {
            return outfits.first { $0.id == uuid }
        }

        if isHex(cleaned), cleaned.count >= 4, cleaned.count <= 8 {
            let matches = outfits.filter { $0.id.uuidString.lowercased().hasPrefix(cleaned) }
            return matches.count == 1 ? matches.first : nil
        }

        return nil
    }

    private static func isHex(_ s: String) -> Bool {
        s.allSatisfy { $0.isHexDigit }
    }

    // Flag aliases that collide within the current wardrobe snapshot. Used only in debug
    // to surface the rare case where aliasLength needs widening.
    static func detectAliasCollisions(in items: [ClothingItem]) -> [String] {
        var seen: [String: Int] = [:]
        for item in items { seen[alias(for: item), default: 0] += 1 }
        return seen.filter { $0.value > 1 }.keys.sorted()
    }

    // MARK: - Description Matching

    // Resolves a free-form description to an item. Alias fast-path tried first, then
    // fuzzy word overlap on type/color/category/fabric/pattern. Fallback only — prefer
    // resolveAlias when the caller already has an ID.
    static func matchItem(description: String, in items: [ClothingItem]) -> ClothingItem? {
        for token in description.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
            if let match = resolveAlias(String(token), in: items) {
                return match
            }
        }

        let descWords = normalizeMatchWords(description)
        guard !descWords.isEmpty else { return nil }

        let scored = items.map { item -> (ClothingItem, Int) in
            let fieldText = [
                item.type, item.primaryColor, item.secondaryColor ?? "",
                item.category, item.pattern, item.fabricEstimate,
                item.itemDescription
            ].joined(separator: " ")
            let fieldWords = normalizeMatchWords(fieldText)
            let score = descWords.filter { fieldWords.contains($0) }.count
            return (item, score)
        }
        return scored.filter { $0.1 > 0 }.max(by: { $0.1 < $1.1 })?.0
    }

    private static let matchStopWords: Set<String> = [
        "the", "a", "an", "my", "your", "with", "and", "of", "in", "on"
    ]

    static func normalizeMatchWords(_ text: String) -> Set<String> {
        let tokens = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !matchStopWords.contains($0) }
        return Set(tokens.map(normalizeToken))
    }

    // Collapses common plural/inflected suffixes so "loafers"/"loafer" and "shoes"/"shoe" match.
    nonisolated static func normalizeToken(_ t: String) -> String {
        if t.count > 4, t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.count > 3, t.hasSuffix("es") { return String(t.dropLast(2)) }
        if t.count > 3, t.hasSuffix("s") { return String(t.dropLast()) }
        return t
    }

    // MARK: - Outfit Resolution

    // Name-based resolution across conversation-generated + saved outfits. Used when the
    // agent cites an outfit by name/occasion rather than outfit_id.
    static func resolveOutfit(
        named name: String,
        conversationMessages: [ChatMessage],
        pendingOutfitItems: [UUID: [ClothingItem]],
        savedOutfits: [Outfit]
    ) -> Outfit? {
        let allConversationOutfits = conversationMessages.flatMap(\.outfits).reversed()
        if !name.isEmpty {
            let lowered = name.lowercased()
            if let match = allConversationOutfits.first(where: {
                $0.displayName.lowercased().contains(lowered) ||
                ($0.occasion?.lowercased().contains(lowered) ?? false)
            }) {
                return match
            }
        }
        if let conversationFallback = allConversationOutfits.first(where: { pendingOutfitItems[$0.id] != nil })
            ?? allConversationOutfits.first {
            return conversationFallback
        }
        if !name.isEmpty {
            let lowered = name.lowercased()
            return savedOutfits.first {
                $0.displayName.lowercased().contains(lowered) ||
                ($0.occasion?.lowercased().contains(lowered) ?? false)
            }
        }
        return nil
    }
}
