import Foundation
import UIKit

enum AnthropicError: LocalizedError {
    case invalidImage
    case networkError(Error)
    case apiError(Int, String)
    case decodingError(String)
    case emptyResults
    case insufficientWardrobe
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to process the image."
        case .networkError:
            return "Unable to connect. Check your internet connection."
        case .apiError:
            return "Something went wrong. Please try again."
        case .decodingError(let detail):
            return "Failed to parse the response: \(detail)"
        case .emptyResults:
            return "No clothing items detected. Try a clearer photo."
        case .insufficientWardrobe:
            return "Add more items to your wardrobe before generating outfits."
        case .insufficientData:
            return "Not enough wardrobe data for style analysis. Add more items."
        }
    }
}

struct DuplicateResult {
    let existingItem: ClothingItem
    let classification: DuplicateClassification
    let explanation: String
}

enum DuplicateClassification: String, Codable {
    case sameItem = "same_item"
    case similar = "similar"
    case noMatch = "no_match"
}

struct AnthropicService {
    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-20250514"
    private static let maxTokens = 4096

    private static let analysisPrompt = """
    Analyze this image and identify every clothing item visible. For each item, return a JSON object with these fields:

    - type: specific item type (e.g., "Crew Neck T-Shirt", "Slim Jeans", "Chelsea Boots")
    - category: one of "Top", "Bottom", "Outerwear", "Footwear", "Accessory", "Full Body" (for dresses, jumpsuits)
    - primary_color: the dominant color (e.g., "Navy Blue", "Charcoal", "Cream")
    - secondary_color: accent or secondary color if present, otherwise null
    - pattern: one of "Solid", "Striped", "Plaid", "Floral", "Graphic", "Abstract", "Polka Dot", "Geometric", "Camo", "Other"
    - fabric_estimate: best guess at material (e.g., "Cotton", "Denim", "Wool", "Polyester", "Linen", "Leather", "Suede", "Silk", "Knit", "Fleece")
    - weight: one of "Lightweight", "Midweight", "Heavyweight"
    - formality: one of "Casual", "Smart Casual", "Business Casual", "Business", "Formal"
    - season: array of applicable seasons from ["Spring", "Summer", "Fall", "Winter"]
    - fit: one of "Slim", "Regular", "Relaxed", "Oversized", "Cropped", or null if not determinable
    - statement_level: one of "Low", "Medium", "High" — how much visual attention the piece draws
    - description: a brief one-sentence description of the item, noting any distinguishing features (graphics, logos, unique details, texture, visible wear, etc.)
    - formality_floor: one of "Black Tie", "Formal", "Cocktail", "Business", or null. Set this ONLY for items inherently tied to a specific formality level that would be inappropriate below it (tuxedo jacket → "Black Tie", evening gown → "Formal", French-cuff dress shirt → "Business"). Most items should be null.

    Return ONLY a valid JSON array of objects. No markdown, no explanation, no code fences. Just the raw JSON array.

    If no clothing items are detected, return an empty array: []
    """

    private static func buildScanPrompt(availableItemTagNames: [String]) -> String {
        var prompt = analysisPrompt
        if !availableItemTagNames.isEmpty {
            // Insert tags field before the "Return ONLY" line by appending at end of field list
            let tagSection = """

            - tags: array of 1-3 tag name strings chosen from this exact list that match the item: [\(availableItemTagNames.joined(separator: ", "))]. Pick tags that describe the item's usage, seasonality, or character. Return an empty array if no tags fit.
            """
            // Insert before the final instruction
            prompt = prompt.replacingOccurrences(
                of: "Return ONLY a valid JSON array",
                with: tagSection + "\nReturn ONLY a valid JSON array"
            )
        }
        return prompt
    }

    // MARK: - Clothing Analysis

    static func analyzeClothing(image: UIImage, availableItemTagNames: [String] = []) async throws -> [ClothingItemDTO] {
        let apiKey = try ConfigManager.apiKey()

        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            throw AnthropicError.invalidImage
        }

        let base64Image = jpegData.base64EncodedString()

        let prompt = buildScanPrompt(availableItemTagNames: availableItemTagNames)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        let items: [ClothingItemDTO]
        do {
            items = try JSONDecoder().decode([ClothingItemDTO].self, from: jsonData)
        } catch {
            throw AnthropicError.decodingError(error.localizedDescription)
        }

        return items
    }

    // MARK: - Single-Image Clothing Analysis with Outfit Detection

    private static let outfitDetectionReturnFormat = """

    OUTFIT DETECTION:
    After identifying all items, assess whether the items in this image form a cohesive outfit \
    (e.g., a full-body photo of a person wearing a complete look, a styled flat-lay, a mannequin display). \
    If yes, include an "outfit" object in the response. If no, set "outfit" to null.

    Do NOT suggest an outfit if the image only shows isolated items (e.g., a single shirt on a hanger, \
    items clearly from different contexts, items laid out individually without styling intent). \
    Only suggest an outfit when the items are clearly styled together as a deliberate combination.

    Return ONLY a valid JSON object (NOT a plain array) with this structure:
    {
      "items": [ ...array of item objects as described above... ],
      "outfit": {
        "name": "short evocative name (e.g., 'Weekend Brunch', 'Office Sharp')",
        "occasion": "one of Casual, Smart Casual, Business Casual, Business, Formal, Cocktail",
        "reasoning": "one sentence explaining why these items work together as an outfit"
      }
    }

    Set "outfit" to null if the items do not form a cohesive outfit.

    No markdown, no explanation, no code fences. Just the raw JSON object.

    If no clothing items are detected, return: {"items": [], "outfit": null}
    """

    private static func buildScanWithOutfitDetectionPrompt(availableItemTagNames: [String]) -> String {
        // Take the base analysis prompt but strip the return format instructions
        var prompt = analysisPrompt
            .replacingOccurrences(
                of: "\n    Return ONLY a valid JSON array of objects. No markdown, no explanation, no code fences. Just the raw JSON array.\n\n    If no clothing items are detected, return an empty array: []",
                with: ""
            )

        if !availableItemTagNames.isEmpty {
            let tagSection = """

            - tags: array of 1-3 tag name strings chosen from this exact list that match the item: [\(availableItemTagNames.joined(separator: ", "))]. Pick tags that describe the item's usage, seasonality, or character. Return an empty array if no tags fit.
            """
            prompt += tagSection
        }

        prompt += outfitDetectionReturnFormat
        return prompt
    }

    static func analyzeClothingWithOutfitDetection(
        image: UIImage,
        availableItemTagNames: [String] = []
    ) async throws -> ScanResponseDTO {
        let apiKey = try ConfigManager.apiKey()

        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            throw AnthropicError.invalidImage
        }

        let base64Image = jpegData.base64EncodedString()

        let prompt = buildScanWithOutfitDetectionPrompt(availableItemTagNames: availableItemTagNames)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        // Try wrapper format first, fall back to flat array
        if let response = try? JSONDecoder().decode(ScanResponseDTO.self, from: jsonData) {
            return response
        }

        let items = try JSONDecoder().decode([ClothingItemDTO].self, from: jsonData)
        return ScanResponseDTO(items: items, outfit: nil)
    }

    // MARK: - Multi-Image Clothing Analysis

    private static let multiImageAddendum = """

    MULTI-IMAGE SCAN:
    You are analyzing multiple images at once. The same clothing item may appear in more than one image.
    - For each unique clothing item detected across ALL images, return ONE entry.
    - Include a "source_image_indices" field: a JSON array of zero-based image indices where this item is visible. Example: [0, 2] means the item appears in image 0 and image 2.
    - If the same item appears in multiple images, merge your observations and use the best view for attribute detection.
    - Do NOT create duplicate entries for the same physical garment seen in different images.
    """

    static func analyzeClothingMultiImage(
        images: [UIImage],
        availableItemTagNames: [String] = []
    ) async throws -> [ClothingItemDTO] {
        let apiKey = try ConfigManager.apiKey()

        var contentBlocks: [[String: Any]] = []

        for (index, image) in images.enumerated() {
            guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
                throw AnthropicError.invalidImage
            }

            let base64Image = jpegData.base64EncodedString()

            contentBlocks.append([
                "type": "text",
                "text": "Image \(index):"
            ])
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
        }

        let prompt = buildScanPrompt(availableItemTagNames: availableItemTagNames) + multiImageAddendum

        contentBlocks.append([
            "type": "text",
            "text": prompt
        ])

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": contentBlocks
                ]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        let items: [ClothingItemDTO]
        do {
            items = try JSONDecoder().decode([ClothingItemDTO].self, from: jsonData)
        } catch {
            throw AnthropicError.decodingError(error.localizedDescription)
        }

        return items
    }

    // MARK: - Duplicate Detection

    static func checkDuplicates(
        scannedItem: ClothingItemDTO,
        candidates: [ClothingItem],
        image: UIImage
    ) async throws -> [DuplicateResult] {
        let apiKey = try ConfigManager.apiKey()

        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            throw AnthropicError.invalidImage
        }

        let base64Image = jpegData.base64EncodedString()

        var candidateDescriptions = ""
        for (index, candidate) in candidates.enumerated() {
            candidateDescriptions += """
            [\(index)] \(candidate.type) - \(candidate.category), \(candidate.primaryColor), \
            \(candidate.pattern), \(candidate.fabricEstimate). \(candidate.itemDescription)\n
            """
        }

        let prompt = """
        I just scanned a clothing item from this image. It was detected as:
        Type: \(scannedItem.type)
        Category: \(scannedItem.category)
        Color: \(scannedItem.primaryColor)
        Pattern: \(scannedItem.pattern)
        Fabric: \(scannedItem.fabricEstimate)
        Description: \(scannedItem.description)

        I have these existing items in my wardrobe that might be the same item:
        \(candidateDescriptions)

        For each existing item, determine if it is the SAME physical item as the scanned one, \
        just SIMILAR (same type but a different garment), or NO MATCH at all.

        Return a JSON array with one object per candidate:
        [{"index": 0, "classification": "same_item"|"similar"|"no_match", "explanation": "brief reason"}]

        Return ONLY valid JSON. No markdown, no explanation, no code fences.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else {
            return []
        }

        var results: [DuplicateResult] = []
        for entry in rawArray {
            guard let index = entry["index"] as? Int,
                  let classStr = entry["classification"] as? String,
                  let classification = DuplicateClassification(rawValue: classStr),
                  let explanation = entry["explanation"] as? String,
                  index < candidates.count
            else { continue }

            results.append(DuplicateResult(
                existingItem: candidates[index],
                classification: classification,
                explanation: explanation
            ))
        }

        return results
    }

    // MARK: - Outfit Generation

    private static let outfitGenerationPrompt = """
    You are a personal stylist. Based on the clothing items listed below, suggest exactly 1 complete outfit combination.

    Rules:
    - The outfit must have 3 to 6 items
    - Include exactly one pair of footwear (if available)
    - Include either one bottom OR one full body item (dress/jumpsuit), not both
    - Include 1-2 tops (unless a full body item is selected). When including 2 tops, they must be \
    different layer weights — pair a base layer (t-shirt, button-up, blouse) with a mid-layer \
    (sweater, cardigan, hoodie), NOT two mid-layers together (e.g., hoodie + pullover sweater is wrong). \
    If COMFORT CONSTRAINTS below indicate "Minimal layers" or "Happy to layer", prefer just 1 top. \
    Only pair 2 tops when the user explicitly loves layering or weather demands it.
    - Include 0-2 outerwear pieces depending on season
    - Include 0-2 accessories to complete the look
    - Each item ID must be unique — do not use the same item twice
    - Limit to 3-4 colors maximum across the entire outfit
    - Avoid mixing more than 2 patterns
    - Keep formality level consistent across all items
    - When weather context is provided, prioritize weather-appropriate choices:
      - Below 5°C: include outerwear, prioritize heavyweight fabrics, avoid linen/lightweight items
      - 5–15°C: include a layer (jacket or cardigan), favor midweight fabrics
      - 15–24°C: light layering optional, midweight fabrics suitable
      - Above 24°C: prioritize lightweight fabrics (linen, cotton), minimize layers
      - If precipitation chance > 50%, prefer items suitable for rain (avoid suede, prefer water-resistant outerwear)
      - If UV index > 6, consider accessories like hats
    - If existing outfits are listed below, do NOT suggest the same item combination — create something different

    Return ONLY a valid JSON array with exactly one element. The element must have:
    - "name": a short, evocative outfit name (e.g., "Weekend Casual", "Office Ready", "Evening Out")
    - "occasion": one of "Casual", "Smart Casual", "Business Casual", "Business", "Formal", "Cocktail", "Black Tie", "White Tie", "Gym/Athletic", "Outdoor/Active"
    - "item_ids": array of item id strings from the list below (use ONLY the provided IDs, do not invent new ones)
    - "reasoning": one sentence explaining why this combination works, including a styling tip. If the wardrobe lacks ideal items for the occasion, acknowledge the compromise
    - "spoken_summary": a natural, conversational 1-2 sentence description of the outfit suitable for voice output (e.g., "I'd go with your navy blazer over the white oxford, paired with dark jeans and brown Chelsea boots — polished but relaxed.")
    - "tags": array of 1-3 tag name strings chosen from the available tags list (empty array if no tags list provided)
    - "wardrobe_gaps": array of strings — helpful investment suggestions for item types missing from the wardrobe for this occasion (empty array if the wardrobe fully covers the occasion). Each string should be a concise suggestion like "Consider adding formal dress shoes for black-tie events."

    No markdown, no explanation, no code fences. Just the raw JSON array.
    """

    static func generateOutfits(
        from items: [ClothingItem],
        occasion: String?,
        season: String?,
        weatherContext: String? = nil,
        comfortPreferences: String? = nil,
        styleSummary: String? = nil,
        filterContext: OccasionFilterContext? = nil,
        existingOutfitItemSets: [[String]] = [],
        availableTagNames: [String] = [],
        observationContext: String? = nil,
        itemRelevanceHints: [UUID: Double]? = nil,
        mustIncludeItemIDs: Set<String> = [],
        styleMode: StyleModePreference? = nil,
        styleDirection: StyleDirection? = nil
    ) async throws -> [OutfitSuggestionDTO] {
        guard items.count >= 2 else {
            throw AnthropicError.insufficientWardrobe
        }

        let apiKey = try ConfigManager.apiKey()

        // Build context BEFORE items so constraints are prominent
        var contextSection = ""

        // Occasion / dress code (structured block replaces plain text)
        if let filterContext {
            contextSection += "\(filterContext.tier.dressCodeInstructions)\n"
            contextSection += "\(filterContext.tier.priorityHierarchy)\n\n"
        } else if let occasion {
            contextSection += "Occasion preference: \(occasion)\n\n"
        }

        if let comfortPreferences {
            contextSection += "COMFORT CONSTRAINTS (override style preferences when conflicting):\n\(comfortPreferences)\n\n"
        }

        // Style summary with weight label based on occasion
        if let styleSummary {
            if let filterContext {
                contextSection += "\(filterContext.tier.styleWeightInstruction)\n\(styleSummary)\n\n"
            } else {
                contextSection += "USER STYLE PROFILE (use as guidance):\n\(styleSummary)\n\n"
            }
        }

        if let observationContext {
            contextSection += "USER BEHAVIORAL PATTERNS:\n\(observationContext)\n"
            contextSection += "Respect these patterns unless they conflict with dress code requirements.\n\n"
        }

        if let styleMode {
            let styleModeText: String
            switch styleMode {
            case .improve:
                var text = """
                STYLE MODE — IMPROVE:
                Steer this outfit toward polished, refined aesthetics (preppy, smart casual, business casual). \
                Even if the wardrobe skews casual or eclectic, prioritize combinations that feel put-together \
                and elevated. Avoid overly casual combinations when more polished options are available. \
                Temperature sensitivity, layering preferences, and all comfort constraints above still take priority.
                """
                if let styleDirection {
                    text += "\n\(styleDirection.promptDescription)"
                }
                styleModeText = text
            case .expand:
                styleModeText = """
                STYLE MODE — EXPAND:
                Infer the user's personal style from the items they own and their saved outfits. \
                Generate suggestions consistent with and expressive of their established aesthetic. \
                Trust the style signals in their wardrobe rather than pushing toward a generic ideal.
                """
            }
            contextSection += "\(styleModeText)\n\n"
        }

        if !mustIncludeItemIDs.isEmpty {
            contextSection += "MUST-INCLUDE CONSTRAINT: The outfit MUST contain all items marked [MUST INCLUDE] below. Build the outfit around these anchor pieces. Do not omit them.\n\n"
        }

        if let season { contextSection += "Current season: \(season)\n" }
        if let weatherContext { contextSection += "Current weather:\n\(weatherContext)\n" }

        // Wardrobe limitation notice when filters were relaxed
        if let filterContext, !filterContext.wardrobeGaps.isEmpty {
            contextSection += "\nWARDROBE LIMITATIONS:\n"
            contextSection += "The user's wardrobe lacks ideal items for this occasion. Compromises were made:\n"
            for gap in filterContext.wardrobeGaps {
                contextSection += "- \(gap.category): \(gap.description)\n"
            }
            contextSection += "Work with the available items and select the most appropriate options. Acknowledge compromises in your reasoning.\n"
            contextSection += "Include wardrobe gap suggestions in the \"wardrobe_gaps\" field.\n"
        }

        var itemList = ""
        for item in items {
            itemList += "- id:\(item.id.uuidString) | \(item.type) | \(item.category) | \(item.primaryColor)"
            if let secondary = item.secondaryColor {
                itemList += "/\(secondary)"
            }
            itemList += " | \(item.pattern) | \(item.fabricEstimate) | \(item.formality) | seasons:\(item.season.joined(separator: ","))"
            itemList += " | \(item.itemDescription)"
            if mustIncludeItemIDs.contains(item.id.uuidString) {
                itemList += " | [MUST INCLUDE]"
            } else if let score = itemRelevanceHints?[item.id], score > 0.7 {
                itemList += " | [STRONG MATCH]"
            }
            itemList += "\n"
        }

        // Dedup section — existing outfit item-ID sets
        var dedupSection = ""
        let relevantSets = existingOutfitItemSets.filter { !$0.isEmpty }
        if !relevantSets.isEmpty {
            dedupSection = "\nEXISTING OUTFITS (do NOT suggest these combinations):\n"
            for (index, ids) in relevantSets.prefix(20).enumerated() {
                dedupSection += "  Outfit \(index + 1): [\(ids.joined(separator: ", "))]\n"
            }
        }

        var tagSection = ""
        if !availableTagNames.isEmpty {
            tagSection = "\nAVAILABLE TAGS — assign 1-3 tags from this exact list that match the outfit:\n"
            tagSection += availableTagNames.joined(separator: ", ")
            tagSection += "\n"
        }

        let fullPrompt = outfitGenerationPrompt + "\n\n" + contextSection + tagSection + "\nAvailable items:\n" + itemList + dedupSection

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": fullPrompt]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        let suggestions: [OutfitSuggestionDTO]
        do {
            suggestions = try JSONDecoder().decode([OutfitSuggestionDTO].self, from: jsonData)
        } catch {
            throw AnthropicError.decodingError(error.localizedDescription)
        }

        if suggestions.isEmpty {
            throw AnthropicError.emptyResults
        }

        return suggestions
    }

    // MARK: - Anchor Outfit Generation

    private static let anchoredOutfitPrompt = """
    You are a personal stylist. Generate 1 to 4 complete outfits built around the anchor item described below.

    COUNT GUIDANCE — choose the number based on these signals:
    - Item versatility: basics (white shirt, navy trouser) support more combinations than single-use items \
    (tuxedo jacket, ski vest). A versatile anchor can support 3–4 outfits; a single-use item may only support 1.
    - Statement level: bold color, unusual texture, or loud pattern limits coherent combinations — generate \
    fewer outfits rather than forcing weak suggestions.
    - Wardrobe depth (when wardrobe items are provided): if the wardrobe is sparse or mismatched for this \
    anchor, generate fewer outfits. If it supports both casual and formal pairings, use that range.
    RULE: never generate an outfit just to hit a higher number. Fewer strong outfits beat more weak ones.

    Each outfit item must specify its source:
    - "wardrobe": an item from the provided wardrobe list — set wardrobe_item_id to the exact ID from the list
    - "suggested": a recommended item the user doesn't own — set wardrobe_item_id to null, and write a \
    specific description (color, fabric, cut)

    If no wardrobe list is provided, all non-anchor items must be "suggested".
    The anchor item itself should always appear as an item in each outfit.

    If the anchor item is difficult to reconcile with the active style direction, note this briefly in the \
    styling_note rather than ignoring the direction silently.

    Return ONLY a valid JSON array. Each element must have:
    - "title": a descriptive label, e.g. "Smart Casual — Weekend Lunch"
    - "occasion": one of "Casual", "Smart Casual", "Business Casual", "Business", "Formal", "Cocktail", \
    "Black Tie", "White Tie", "Gym/Athletic", "Outdoor/Active"
    - "items": array of outfit pieces, each with:
        - "source": "wardrobe" or "suggested"
        - "wardrobe_item_id": string UUID or null
        - "category": one of "Top", "Bottom", "Outerwear", "Footwear", "Accessory", "Full Body"
        - "description": item description — for wardrobe items restate the type and color; for suggested \
    items be specific (color, fabric, cut)
        - "why_it_works": one sentence on how it complements the anchor item
    - "styling_note": one optional tip on how to wear the full look (e.g. tuck, roll, layer). Can be null.

    Rules:
    - Each outfit must have 3–6 items total (including the anchor)
    - Include footwear in each outfit unless the anchor IS footwear
    - Keep total look to 3–4 colors
    - Keep formality consistent within each outfit (unless occasion overrides)
    - No markdown, no explanation, no code fences. Just the raw JSON array.
    """

    static func generateAnchoredOutfits(
        anchor: ClothingItem,
        wardrobeItems: [ClothingItem],
        occasion: String?,
        weatherContext: String? = nil,
        styleSummary: String? = nil,
        styleMode: StyleModePreference? = nil,
        styleDirection: StyleDirection? = nil
    ) async throws -> [AnchorOutfitResultDTO] {
        let apiKey = try ConfigManager.apiKey()

        var contextSection = ""

        if let occasion {
            contextSection += "Occasion constraint: \(occasion)\n\n"
        }

        if let styleSummary {
            contextSection += "USER STYLE PROFILE (use as guidance):\n\(styleSummary)\n\n"
        }

        if let styleMode {
            let styleModeText: String
            switch styleMode {
            case .improve:
                var text = """
                STYLE MODE — IMPROVE:
                Steer outfits toward polished, refined aesthetics (preppy, smart casual, business casual). \
                Even if the anchor item skews casual, prioritize suggestions that feel put-together and elevated. \
                Comfort constraints still take priority.
                """
                if let styleDirection {
                    text += "\n\(styleDirection.promptDescription)"
                }
                styleModeText = text
            case .expand:
                styleModeText = """
                STYLE MODE — EXPAND:
                Infer the user's aesthetic from the anchor item's style signals. \
                Generate suggestions consistent with and expressive of that direction. \
                Trust the anchor's style signals rather than pushing toward a generic ideal.
                """
            }
            contextSection += "\(styleModeText)\n\n"
        }

        if let weatherContext {
            contextSection += "Current weather:\n\(weatherContext)\n\n"
        }

        // Anchor item
        var anchorLine = "ANCHOR ITEM:\n"
        anchorLine += "- id:\(anchor.id.uuidString) | \(anchor.type) | \(anchor.category) | \(anchor.primaryColor)"
        if let secondary = anchor.secondaryColor { anchorLine += "/\(secondary)" }
        anchorLine += " | \(anchor.pattern) | \(anchor.fabricEstimate) | \(anchor.statementLevel) statement"
        anchorLine += " | \(anchor.formality) | \(anchor.itemDescription)"

        // Wardrobe items (when present)
        var wardrobeSection = ""
        if !wardrobeItems.isEmpty {
            wardrobeSection = "\n\nAVAILABLE WARDROBE ITEMS (use wardrobe_item_id from these IDs):\n"
            for item in wardrobeItems where item.id != anchor.id {
                wardrobeSection += "- id:\(item.id.uuidString) | \(item.type) | \(item.category) | \(item.primaryColor)"
                if let secondary = item.secondaryColor { wardrobeSection += "/\(secondary)" }
                wardrobeSection += " | \(item.fabricEstimate) | \(item.formality)\n"
            }
        }

        let fullPrompt = anchoredOutfitPrompt + "\n\n" + contextSection + anchorLine + wardrobeSection

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": fullPrompt]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        do {
            let outfits = try JSONDecoder().decode([AnchorOutfitResultDTO].self, from: jsonData)
            if outfits.isEmpty { throw AnthropicError.emptyResults }
            return outfits
        } catch {
            throw AnthropicError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Style Analysis

    private static let styleAnalysisPrompt = """
    You are a personal style analyst. Based on the wardrobe data below, produce a comprehensive style profile.

    INSTRUCTIONS:
    - Analyze the user's clothing items, outfit choices, and stated preferences to identify their style identity.
    - Weight signals in this order of importance:
      1. USER-DECLARED PREFERENCES are ground truth — never contradict these.
      2. FAVORITED OUTFITS reflect intentional style choices — strongest behavioral signal.
      3. MANUALLY CREATED OUTFITS show deliberate pairing decisions.
      4. AI-GENERATED OUTFITS are suggestions the user kept but may not fully represent preference.
      5. Individual wardrobe items show what they own but not necessarily how they prefer to wear it.
    - Detect 1-3 distinct style modes organically from the data. Do not force a fixed count — some users have one cohesive style, others have 3-4 modes. Derive modes primarily from favorited outfit clusters.
    - Each style mode needs: a descriptive name, a 1-2 sentence description, a color palette (3-5 dominant color names from their wardrobe that define this mode), and a formality level.
    - If there is insufficient data for a field, return null rather than guessing.

    Return ONLY a valid JSON object with these fields:
    - "overall_identity": 2-4 sentences capturing the user's dominant aesthetic, color tendencies, and formality range
    - "style_modes": array of objects with "name" (string), "description" (string), "color_palette" (array of color name strings matching wardrobe colors), "formality" (one of "Casual", "Smart Casual", "Business Casual", "Business", "Formal")
    - "temporal_notes": string or null — any directional shifts in recent items/favorites vs older ones, framed as observations not identity rewrites
    - "gap_observations": string or null — wardrobe gaps and opportunities
    - "weather_behavior": string or null — seasonal-relative dressing patterns detected from outfit weather data

    No markdown, no explanation, no code fences. Just the raw JSON object.
    """

    private static let incrementalAnalysisAddendum = """

    IMPORTANT — INCREMENTAL ANALYSIS:
    A previous style analysis exists (shown below). Treat it as the baseline identity. Style evolves gradually — only adjust the profile where new evidence is compelling. Do not radically change the overall identity based on a few new items. Preserve established patterns unless the data clearly contradicts them.
    """

    static func analyzeStyle(
        items: [ClothingItem],
        outfits: [Outfit],
        profile: UserProfile?,
        existingSummary: StyleSummary?
    ) async throws -> StyleAnalysisDTO {
        guard items.count >= 8 else {
            throw AnthropicError.insufficientData
        }

        let apiKey = try ConfigManager.apiKey()

        let isIncremental = existingSummary != nil
        let lastAnalyzedAt = existingSummary?.lastAnalyzedAt

        var itemList: String
        if isIncremental, let lastAnalyzedAt {
            // Tier 1: Favorite items — appear in at least one favorited outfit
            let favoritedOutfitItems = Set(
                outfits.filter { $0.isFavorite }.flatMap { $0.items }
                    .map { $0.id }
            )
            let favoriteItems = items.filter { favoritedOutfitItems.contains($0.id) }

            // Tier 2: New items since last analysis (excluding favorites already captured)
            let favoriteIDs = Set(favoriteItems.map { $0.id })
            let newItems = items.filter {
                $0.createdAt > lastAnalyzedAt && !favoriteIDs.contains($0.id)
            }

            // Tier 3: Everything else — compact summary
            let allDetailedIDs = favoriteIDs.union(Set(newItems.map { $0.id }))
            let existingItems = items.filter { !allDetailedIDs.contains($0.id) }

            itemList = ""
            if !favoriteItems.isEmpty {
                itemList += "FAVORITE ITEMS (appear in favorited outfits — highest signal, \(favoriteItems.count) items):\n"
                itemList += formatItemList(favoriteItems)
            }
            if !newItems.isEmpty {
                itemList += "\nNEW ITEMS SINCE LAST ANALYSIS (\(newItems.count) items):\n"
                itemList += formatItemList(newItems)
            }
            if !existingItems.isEmpty {
                itemList += "\nEXISTING WARDROBE SUMMARY (\(existingItems.count) items, details omitted — see previous analysis):\n"
                itemList += formatCompactItemSummary(existingItems)
            }
        } else {
            // Initial analysis: send all items, capped at 60
            let cappedItems = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(60))
            itemList = "WARDROBE ITEMS (\(cappedItems.count) items):\n"
            itemList += formatItemList(cappedItems)
        }

        // Tier outfits by signal strength
        let favorited = Array(outfits.filter { $0.isFavorite }.prefix(10))
        let manualNonFav = Array(outfits.filter { !$0.isAIGenerated && !$0.isFavorite }.prefix(5))
        let aiNonFav = Array(outfits.filter { $0.isAIGenerated && !$0.isFavorite }.prefix(5))

        var outfitSection = ""
        if !favorited.isEmpty {
            outfitSection += "\nFAVORITED OUTFITS (highest weight — the user's self-identified best outfits):\n"
            outfitSection += formatOutfitList(favorited)
        }
        if !manualNonFav.isEmpty {
            outfitSection += "\nMANUALLY CREATED OUTFITS (deliberate pairing decisions):\n"
            outfitSection += formatOutfitList(manualNonFav)
        }
        if !aiNonFav.isEmpty {
            outfitSection += "\nAI-GENERATED OUTFITS (accepted suggestions):\n"
            outfitSection += formatOutfitList(aiNonFav)
        }

        // User preferences
        var preferencesSection = ""
        if let profile {
            var prefs: [String] = []
            let styles = profile.selectedStylesArray
            if !styles.isEmpty { prefs.append("Self-identified styles: \(styles.joined(separator: ", "))") }
            if let cold = profile.coldSensitivityEnum { prefs.append("Cold sensitivity: \(cold.rawValue)") }
            if let heat = profile.heatSensitivityEnum { prefs.append("Heat sensitivity: \(heat.rawValue)") }
            if let notes = profile.bodyTempNotes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                prefs.append("Body temp notes: \(notes.trimmingCharacters(in: .whitespaces))")
            }
            if let layering = profile.layeringPreferenceEnum { prefs.append("Layering: \(layering.rawValue)") }
            if let comfort = profile.comfortVsAppearanceEnum { prefs.append("Comfort vs appearance: \(comfort.rawValue)") }
            if let weather = profile.weatherDressingApproachEnum { prefs.append("Weather dressing: \(weather.rawValue)") }

            if !prefs.isEmpty {
                preferencesSection = "\nUSER-DECLARED PREFERENCES (treat as ground truth — do not contradict):\n"
                    + prefs.joined(separator: "\n") + "\n"
            }
        }

        // Existing summary for incremental analysis — send full details so AI can preserve/evolve
        var existingSummarySection = ""
        if let existingSummary {
            existingSummarySection = "\nPREVIOUS ANALYSIS"
            if existingSummary.isUserEdited {
                existingSummarySection += " (user has personally refined this — weight their edits heavily and preserve their characterizations unless wardrobe data strongly contradicts them)"
            }
            existingSummarySection += ":\n\(existingSummary.overallIdentity)\n"

            let modes = existingSummary.styleModesDecoded
            if !modes.isEmpty {
                existingSummarySection += "Previous style modes:\n"
                for mode in modes {
                    existingSummarySection += "  - \(mode.name) (\(mode.formality)): \(mode.description). Colors: \(mode.colorPalette.joined(separator: ", "))\n"
                }
            }
            if let temporal = existingSummary.temporalNotes {
                existingSummarySection += "Previous temporal notes: \(temporal)\n"
            }
            if let gaps = existingSummary.gapObservations {
                existingSummarySection += "Previous gap observations: \(gaps)\n"
            }
            if let weather = existingSummary.weatherBehavior {
                existingSummarySection += "Previous weather behavior: \(weather)\n"
            }
        }

        let basePrompt = existingSummary != nil
            ? styleAnalysisPrompt + incrementalAnalysisAddendum
            : styleAnalysisPrompt

        let fullPrompt = basePrompt + "\n\n" + preferencesSection + itemList + outfitSection + existingSummarySection

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": fullPrompt]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        let analysis: StyleAnalysisDTO
        do {
            analysis = try JSONDecoder().decode(StyleAnalysisDTO.self, from: jsonData)
        } catch {
            throw AnthropicError.decodingError(error.localizedDescription)
        }

        return analysis
    }

    private static func formatItemList(_ items: [ClothingItem]) -> String {
        var result = ""
        for item in items {
            result += "- \(item.type) | \(item.category) | \(item.primaryColor)"
            if let secondary = item.secondaryColor {
                result += "/\(secondary)"
            }
            result += " | \(item.pattern) | \(item.fabricEstimate) | \(item.formality)"
            result += " | seasons:\(item.season.joined(separator: ","))"
            result += " | \(item.itemDescription)\n"
        }
        return result
    }

    private static func formatCompactItemSummary(_ items: [ClothingItem]) -> String {
        // Group by category
        var categoryGroups: [String: [ClothingItem]] = [:]
        for item in items {
            categoryGroups[item.category, default: []].append(item)
        }

        var result = ""
        for (category, groupItems) in categoryGroups.sorted(by: { $0.key < $1.key }) {
            // Count colors within category
            var colorCounts: [String: Int] = [:]
            for item in groupItems {
                colorCounts[item.primaryColor, default: 0] += 1
            }
            let topColors = colorCounts.sorted { $0.value > $1.value }.prefix(3)
                .map { "\($0.key)(\($0.value))" }.joined(separator: ", ")
            result += "- \(groupItems.count) \(category) items; dominant colors: \(topColors)\n"
        }
        return result
    }

    private static func formatOutfitList(_ outfits: [Outfit]) -> String {
        var result = ""
        for outfit in outfits {
            result += "  Outfit: \(outfit.displayName)"
            if let occasion = outfit.occasion { result += " (\(occasion))" }
            result += "\n"
            if let temp = outfit.weatherTempAtCreation {
                result += "    Weather at creation: \(Int(temp))°C"
                if let feelsLike = outfit.weatherFeelsLikeAtCreation {
                    result += " (feels like \(Int(feelsLike))°C)"
                }
                if let season = outfit.seasonAtCreation { result += ", \(season)" }
                if let month = outfit.monthAtCreation { result += ", month \(month)" }
                result += "\n"
            }
            for item in outfit.items {
                result += "    - \(item.type) | \(item.category) | \(item.primaryColor) | \(item.formality)\n"
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func sendRequest(body: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.apiError(httpResponse.statusCode, responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw AnthropicError.decodingError("Unexpected response structure.")
        }

        return text
    }

    // MARK: - Agent Request

    static func sendAgentRequest(body: [String: Any], apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.apiError(httpResponse.statusCode, responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicError.decodingError("Unexpected response structure.")
        }

        return json
    }

    // MARK: - Streaming Agent Request

    static func streamAgentRequest(body: [String: Any], apiKey: String) async throws -> URLSession.AsyncBytes {
        var streamBody = body
        streamBody["stream"] = true

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: streamBody)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // Consume the error body for a better error message
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 4096 { break }
            }
            let responseBody = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.apiError(httpResponse.statusCode, responseBody)
        }

        return bytes
    }

    private static func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
