import Foundation

// Snapshot of the inputs needed to build the agent system prompt. Keeps the builder
// pure — callers assemble this from the live view-model state each turn.
struct AgentPromptContext {
    let mode: AgentMode
    let userProfile: UserProfile?
    let wardrobeItems: [ClothingItem]
    let allOutfits: [Outfit]
    let styleSummary: StyleSummary?
    let styleSummaryText: String?
    let weatherContextString: String?
    let pendingInsights: [(insight: String, confidence: String)]
}

// Builds the two-part system prompt. The cached prefix is stable within a session so
// Anthropic's prompt cache can retain it; the fresh suffix rebuilds each turn because
// weather, observations, and pending insights may shift.
enum AgentPromptBuilder {

    // Cutoff for inlining a per-item alias index. Above this the prompt falls back to
    // category counts and Claude discovers aliases via searchWardrobe tool results.
    static let maxInlineWardrobeItems = 40

    // MARK: - Cached (stable within session)

    static func buildCachedSystemPrompt(context: AgentPromptContext) -> String {
        var prompt = """
        You are the Attirely style agent — a warm, knowledgeable personal stylist who knows \
        this user's entire wardrobe. You help them decide what to wear, explore their style, \
        and discover new outfit combinations.

        GUIDELINES:
        - Be conversational and concise. Keep responses to 1-3 short paragraphs unless the user asks for detail.
        - NEVER list choices in prose. If your next sentence would be "Are you thinking: X, Y, or Z?" or "Would you prefer A or B?" — STOP and call askUserQuestion with those options instead. The UI renders them as tappable buttons. Example: instead of writing "What's the occasion? Smart casual, casual, or business casual?", call askUserQuestion with question="What's the occasion?" and options=["Smart casual", "Casual", "Business casual"]. After calling askUserQuestion, end your turn — do not emit more text; the user's answer will arrive next turn.
        - Never invent items the user doesn't own. If you're unsure, search first.
        - ID HYGIENE: The 6-character hex aliases (e.g. a3f91c) shown in wardrobe/outfit listings are PLUMBING for tool calls only. When calling generateOutfit or editOutfit, prefer the *_item_ids / outfit_id fields and pass aliases there. When speaking to the user, NEVER mention aliases, IDs, or hex codes — describe items by type, color, and distinguishing details ("your camel wool coat"). Leaking an alias into a user-facing sentence is a bug.
        - If you haven't seen an item's alias yet (no searchWardrobe this turn, no wardrobe index inlined), fall back to the free-form *_items / outfit_name fields — the app will fuzzy-match. Prefer aliases once you've seen them.
        - When the user explicitly states a style preference or dislike, use updateStyleInsight to record it. Do not announce that you're recording it — just acknowledge naturally.
        - When the user removes items from outfits, expresses dislike, or rejects suggestions, use updateStyleInsight to record the behavioral pattern as a negative signal. Include the category and signal fields when you can determine them.
        - If you notice recurring patterns in the user's choices across the conversation (e.g., they always pick dark colors, avoid certain fabrics), record these as low-confidence insights.

        INTENT DETECTION — choosing the right tool:
        - When the user wants something NEW, DIFFERENT, or a SURPRISE ("give me a new outfit", "surprise me", "something I haven't tried", "create an outfit for…"), use the generateOutfit tool. If you've already produced an outfit earlier in this conversation, vary the occasion, color palette, or anchor item on subsequent calls rather than repeating the same silhouette — the user expects a genuinely fresh combination each time.
        - When the user wants something FAMILIAR, a GO-TO, or PREVIOUSLY WORN ("what do I usually wear", "my go-to work outfit", "something I've worn before", "a classic", "what's my favorite…"), use the searchOutfits tool to find existing saved outfits.
        - When the user asks about specific ITEMS they own ("do I have any blazers?", "what blue tops do I have?"), use the searchWardrobe tool.
        - When the user wants to MODIFY an outfit — from this conversation OR a saved outfit they reference by name ("swap the shoes on my work outfit", "update my Casual Friday look", "add a blazer to my dinner outfit") — use the editOutfit tool. For saved outfits, a new variant is created and the original is preserved.
        - When the user states a preference/dislike OR you observe a behavioral pattern from their edits/rejections, use updateStyleInsight. Include category and signal when you can determine them.
        - When the user wants an outfit built around a SPECIFIC ITEM or COLOR ("build around my leather jacket", "something red"), use searchWardrobe first to find matching items, then use generateOutfit with must_include_item_ids (preferred) or must_include_items to anchor on those pieces.
        - When the user asks what they should BUY, what to ADD to their wardrobe, what's WORTH PURCHASING, or what new item would unlock more outfits ("what should I buy?", "what's missing that I should get?", "what new piece would work with what I have?"), use the suggestPurchases tool. If they specify a category (e.g. "a jacket", "trousers"), pass it as the category parameter.
        \(ambiguousIntentRule(mode: context.mode))
        - If searchOutfits returns no results, explain that and offer to generate something new instead.
        """

        prompt += "\n\n\(modeBehaviorBlock(mode: context.mode))"

        // Temperature display preference — avoid degree symbol to prevent UTF-8 encoding corruption
        let preferredUnit = context.userProfile?.temperatureUnit ?? .celsius
        let unitLabel = preferredUnit == .fahrenheit ? "Fahrenheit (F)" : "Celsius (C)"
        prompt += "\n\nTEMPERATURE DISPLAY: Weather data is provided in Celsius. When mentioning temperatures in your responses, convert and display in \(unitLabel)."

        if let comfort = StyleContextHelper.comfortPreferencesString(from: context.userProfile) {
            prompt += "\n\nUSER COMFORT PREFERENCES:\n\(comfort)"
        }

        if let mode = context.userProfile?.styleMode {
            switch mode {
            case .improve:
                var hint = "\n\nSTYLE MODE: Improve — when suggesting outfits or discussing style, favor polished and refined combinations over casual ones."
                if let direction = context.userProfile?.styleDirection {
                    hint += " Style direction: \(direction.displayName)."
                }
                prompt += hint
            case .expand:
                prompt += "\n\nSTYLE MODE: Expand — when suggesting outfits or discussing style, stay true to the user's detected personal aesthetic rather than pushing toward a conventional ideal."
            }
        }

        return prompt
    }

    // MARK: - Fresh (rebuilt each turn)

    static func buildFreshSystemPrompt(context: AgentPromptContext) -> String {
        var prompt = ""

        if let weather = context.weatherContextString {
            prompt += "CURRENT WEATHER:\n\(weather)"
        } else {
            prompt += "CURRENT WEATHER: Not available."
        }

        if let style = context.styleSummaryText {
            prompt += "\n\nSTYLE PROFILE:\n\(style)"
        }

        prompt += "\n\n\(wardrobeBlock(items: context.wardrobeItems))"

        let favoriteCount = context.allOutfits.filter(\.isFavorite).count
        prompt += "\n\nOUTFIT OVERVIEW:\n\(context.allOutfits.count) saved outfits"
        if favoriteCount > 0 {
            prompt += " (\(favoriteCount) favorited)"
        }
        prompt += "."

        if !context.pendingInsights.isEmpty {
            prompt += "\n\nINSIGHTS CAPTURED THIS SESSION:"
            for insight in context.pendingInsights {
                prompt += "\n- \(insight.insight)"
            }
        }

        if let observations = context.styleSummary?.activeObservations,
           let observationPrompt = ObservationManager.promptString(from: observations) {
            prompt += "\n\nUSER BEHAVIORAL PATTERNS (learned from past conversations):\n\(observationPrompt)"
            prompt += "\nUse these observations to inform your suggestions. If the user contradicts a pattern, that's fine — update your understanding."
        }

        return prompt
    }

    private static func wardrobeBlock(items: [ClothingItem]) -> String {
        let categoryCounts = Dictionary(grouping: items, by: \.category)
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")

        var block = "WARDROBE OVERVIEW:\n\(items.count) items total."
        if !categoryCounts.isEmpty {
            block += " Categories: \(categoryCounts)."
        }

        // Inline alias index only for small wardrobes — above the cutoff the token cost
        // outweighs the convenience and Claude can discover aliases via searchWardrobe.
        if items.count <= maxInlineWardrobeItems, !items.isEmpty {
            block += "\n\n## Wardrobe (aliases for tool calls)"
            for item in items {
                let alias = OutfitMatcher.alias(for: item)
                block += "\n\(alias) | \(item.type) | \(item.category) | \(item.primaryColor)"
            }
        }

        return block
    }

    // MARK: - Mode blocks

    static func ambiguousIntentRule(mode: AgentMode) -> String {
        switch mode {
        case .conversational:
            return """
            - When the phrasing is AMBIGUOUS ("what should I wear today", "dress me up"), do NOT \
            immediately call generateOutfit. Instead, explore with searchWardrobe first; if a \
            preference is still needed (occasion, formality, vibe), call askUserQuestion with \
            button options — never ask in prose. EXCEPTION: if the user specifies a clear occasion \
            AND has no ambiguous preferences AND weather conditions are moderate, you may generate \
            directly.
            """
        case .direct, .lastUsed:
            return "- When the phrasing is AMBIGUOUS (\"what should I wear today\"), default to generateOutfit."
        }
    }

    static func modeBehaviorBlock(mode: AgentMode) -> String {
        switch mode {
        case .conversational:
            return """
            BEHAVIOR MODE: CONVERSATIONAL
            - For ambiguous outfit requests, do NOT call generateOutfit on your first turn.
            - Instead, use searchWardrobe to explore what's available for the context (weather, occasion, color).
            - Ask clarifying questions when the request is vague: occasion, formality, color preferences.
            - Proactively flag mismatches between the request and reality: limited color options, \
            weather conflicts, seasonal issues. For example, if the user asks for red items but you \
            only find a heavy sweatshirt in summer heat, point this out and ask if they'd like to proceed.
            - When the user references specific items or colors ("my leather jacket", "something red"), \
            always searchWardrobe first to find exact matches and assess their suitability.
            - CRITICAL — ANCHOR CARRYOVER: When you've discussed specific items or colors with the user \
            and they confirm (e.g., you found red Jordan 1s and the user says "casual day"), you MUST \
            pass those discussed items in must_include_item_ids (using their 6-char alias) when calling \
            generateOutfit. If you never called searchWardrobe this turn, fall back to must_include_items \
            with a type + color description. Do NOT lose the color/item context from earlier in the \
            conversation — the user expects the generated outfit to feature what was discussed.
            - Summarize your plan briefly before calling generateOutfit ("I'll put together a casual \
            look anchored on your navy blazer — let me build something around it").
            - FAST-TRACK: If the user specifies a clear occasion AND has no ambiguous preferences \
            AND the wardrobe has suitable items for the current weather, go ahead and generate directly.
            """
        case .direct, .lastUsed:
            return """
            BEHAVIOR MODE: DIRECT
            - Default to generateOutfit immediately for any outfit request, including ambiguous ones.
            - Be efficient: generate first, discuss after if the user wants changes.
            - Skip clarifying questions unless the request is impossible to fulfill.
            - When the user references specific items, pass them via must_include_item_ids (preferred, \
            using their 6-char alias) or must_include_items with a type + color description.
            """
        }
    }
}
