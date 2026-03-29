import Foundation

struct AgentService {

    private static let model = "claude-sonnet-4-20250514"
    private static let maxTokens = 2048

    // MARK: - Send Message (single API call, no loop)

    static func sendMessage(
        history: [[String: Any]],
        systemPrompt: String,
        tools: [[String: Any]],
        apiKey: String
    ) async throws -> AgentTurn {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "tools": tools,
            "messages": history
        ]

        let json = try await AnthropicService.sendAgentRequest(body: body, apiKey: apiKey)

        guard let content = json["content"] as? [[String: Any]],
              let stopReason = json["stop_reason"] as? String
        else {
            throw AnthropicError.decodingError("Missing content or stop_reason in agent response.")
        }

        var textParts: [String] = []
        var toolCalls: [ToolUseBlock] = []

        for block in content {
            let blockType = block["type"] as? String
            if blockType == "text", let text = block["text"] as? String {
                textParts.append(text)
            } else if blockType == "tool_use", let toolCall = ToolUseBlock(from: block) {
                toolCalls.append(toolCall)
            }
        }

        return AgentTurn(
            assistantText: textParts.isEmpty ? nil : textParts.joined(separator: "\n"),
            toolCalls: toolCalls,
            rawAssistantContent: content,
            stopReason: stopReason
        )
    }

    // MARK: - Stream Message (SSE)

    static func streamMessage(
        history: [[String: Any]],
        systemPrompt: String,
        tools: [[String: Any]],
        apiKey: String
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "tools": tools,
            "messages": history
        ]

        let bytes = try await AnthropicService.streamAgentRequest(body: body, apiKey: apiKey)
        return SSEStreamParser.parse(bytes: bytes)
    }

    // MARK: - Tool Definitions

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "generateOutfit",
            "description": """
                Generate a complete outfit from the user's wardrobe based on current weather \
                and preferences. Call this when the user asks for outfit suggestions, asks what \
                to wear, or requests an outfit for a specific occasion. When the user wants an \
                outfit built around specific items, use must_include_items to anchor the generation \
                on those pieces. Use searchWardrobe first to verify items exist. Returns a styled \
                outfit with reasoning.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "occasion": [
                        "type": "string",
                        "description": "Optional occasion context. One of: Casual, Smart Casual, Business Casual, Business, Cocktail, Formal, Black Tie, White Tie, Gym/Athletic, Outdoor/Active, or a specific event description."
                    ],
                    "constraints": [
                        "type": "string",
                        "description": "Optional freeform styling constraints from the conversation, e.g. 'avoid heavy fabrics', 'include the navy jacket', 'something comfortable'."
                    ],
                    "must_include_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": """
                            Item descriptions that MUST appear in the generated outfit (e.g., \
                            'black leather jacket', 'red dress'). Use searchWardrobe first to \
                            verify items exist, then reference them here by type and color.
                            """
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "searchOutfits",
            "description": """
                Search the user's saved outfits by name, occasion, or tags. Use this when the \
                user asks for a familiar outfit, a go-to look, something they've worn before, or \
                references existing outfits (e.g. 'my usual work outfit', 'what do I normally \
                wear to the gym', 'find me a formal outfit'). Can filter by tags.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Optional text to match against outfit names, occasions, or item descriptions."
                    ],
                    "tags": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Optional tag names to filter by (e.g. 'formal', 'winter')."
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "searchWardrobe",
            "description": """
                Search the user's wardrobe for specific items matching a description or criteria. \
                Use this when the user asks about specific pieces they own, wants to know what \
                colors or types they have, or asks questions like 'do I have any blazers?'
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Short keyword query using item attributes (color, type, category, fabric, pattern). Examples: 'red', 'blue tops', 'formal shoes', 'linen', 'striped'. Keep it concise — avoid filler words like 'for', 'today', 'weather'."
                    ]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "updateStyleInsight",
            "description": """
                Record a style observation about the user. Use this when: \
                (1) The user EXPLICITLY states a preference or dislike (high confidence), \
                (2) The user's outfit edit reveals a behavioral pattern — e.g. they keep removing \
                sneakers from business outfits (medium confidence), \
                (3) You notice a recurring pattern across the conversation (low confidence). \
                Both positive preferences and negative aversions should be recorded.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "insight": [
                        "type": "string",
                        "description": "Concise statement of the observation. E.g. 'Avoids brown shoes for formal occasions.'"
                    ],
                    "confidence": [
                        "type": "string",
                        "description": "How explicitly the user communicated this.",
                        "enum": ["high", "medium", "low"]
                    ],
                    "category": [
                        "type": "string",
                        "description": "The observation category.",
                        "enum": ["formalityPreference", "colorAversion", "colorPreference", "fabricPreference", "fabricAversion", "occasionBehavior", "itemPreference", "itemAversion", "generalStyle"]
                    ],
                    "signal": [
                        "type": "string",
                        "description": "Whether this is a positive preference or a negative aversion.",
                        "enum": ["positive", "negative"]
                    ]
                ],
                "required": ["insight", "confidence"]
            ]
        ],
        [
            "name": "editOutfit",
            "description": """
                Edit an outfit from this conversation. Use this when the user asks to swap, \
                replace, add, or remove items in an outfit, rename it, or change its occasion. \
                Reference items by their type and color (e.g. 'the sneakers', 'navy blazer'). \
                Use the most recently shown outfit if the user doesn't specify which one.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "outfit_name": [
                        "type": "string",
                        "description": "Name or description of the outfit to edit. Use the most recently shown outfit if ambiguous."
                    ],
                    "remove_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Item descriptions to remove (e.g. 'the sneakers', 'white t-shirt'). Matched by type and color."
                    ],
                    "add_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Wardrobe item descriptions to add (e.g. 'Chelsea boots', 'blue blazer'). Matched against the user's wardrobe by type and color."
                    ],
                    "new_name": [
                        "type": "string",
                        "description": "Optional new name for the outfit."
                    ],
                    "new_occasion": [
                        "type": "string",
                        "description": "Optional new occasion for the outfit."
                    ]
                ],
                "required": ["outfit_name"]
            ]
        ]
    ]
}
