import Foundation

struct AgentService {

    private static let model = "claude-sonnet-4-20250514"
    private static let maxTokens = 4096

    // Build a structured `system` array so the stable prefix can be cached by Anthropic.
    // A single `cache_control: {"type": "ephemeral"}` breakpoint on the cached block caches
    // tools + the cached system block together.
    private static func buildSystemBlocks(
        cached: String,
        fresh: String
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = [[
            "type": "text",
            "text": cached,
            "cache_control": ["type": "ephemeral"]
        ]]
        if !fresh.isEmpty {
            blocks.append(["type": "text", "text": fresh])
        }
        return blocks
    }

    // MARK: - Send Message (single API call, no loop)

    static func sendMessage(
        history: [[String: Any]],
        cachedSystemPrompt: String,
        freshSystemPrompt: String,
        tools: [[String: Any]],
        apiKey: String
    ) async throws -> AgentTurn {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": buildSystemBlocks(cached: cachedSystemPrompt, fresh: freshSystemPrompt),
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
        cachedSystemPrompt: String,
        freshSystemPrompt: String,
        tools: [[String: Any]],
        apiKey: String
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": buildSystemBlocks(cached: cachedSystemPrompt, fresh: freshSystemPrompt),
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
                outfit built around specific items, prefer must_include_item_ids (6-char aliases \
                from searchWardrobe results or the wardrobe index) over must_include_items. \
                Returns a styled outfit with reasoning.
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
                    "must_include_item_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": """
                            Preferred. 6-character hex aliases of items that MUST appear in the \
                            generated outfit (e.g., 'a3f91c', '4c8a11'). Use aliases from \
                            searchWardrobe results or the inlined wardrobe index. Deterministic — \
                            resolves the exact item even when colors/types collide.
                            """
                    ],
                    "must_include_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": """
                            Fallback. Free-form item descriptions (e.g., 'black leather jacket') \
                            — used only when you haven't seen aliases yet. Matched fuzzily; may \
                            pick the wrong one when the user owns multiple similar items. Prefer \
                            must_include_item_ids whenever possible.
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
                Edit an outfit — either from this conversation or a saved outfit from the user's \
                wardrobe. Use this when the user asks to swap, replace, add, or remove items, \
                rename it, or change its occasion. For saved outfits, your edit is shown as a \
                proposed variant; the user picks whether to update the original or save it as a \
                new outfit via buttons under the card. Just perform the edit — never describe it \
                as a failure, as 'not applied', or as a manual copy. Prefer outfit_id / \
                remove_item_ids / add_item_ids (6-char aliases from search results); fall back to \
                outfit_name / remove_items / add_items only when you haven't seen the aliases. \
                Use the most recently shown outfit if the user doesn't specify.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "outfit_id": [
                        "type": "string",
                        "description": "Preferred. 6-character hex alias of the outfit to edit (from searchOutfits results or a generated outfit's tool-result summary)."
                    ],
                    "outfit_name": [
                        "type": "string",
                        "description": "Fallback. Name/description of the outfit to edit — used only when you haven't seen the alias. Use the most recently shown outfit if ambiguous."
                    ],
                    "remove_item_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Preferred. 6-character hex aliases of items to remove from the outfit."
                    ],
                    "remove_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Fallback. Free-form descriptions of items to remove (e.g. 'the sneakers'). Matched fuzzily — may pick wrong when duplicates exist."
                    ],
                    "add_item_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Preferred. 6-character hex aliases of wardrobe items to add to the outfit."
                    ],
                    "add_items": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Fallback. Free-form descriptions of wardrobe items to add (e.g. 'Chelsea boots'). Matched fuzzily — may pick wrong when duplicates exist."
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
                "required": [] as [String]
            ]
        ],
        [
            "name": "suggestPurchases",
            "description": """
                Suggest new clothing items the user could buy to fill wardrobe gaps or strengthen \
                their style. Call this when the user asks what they should buy, what's worth adding, \
                what would fill a gap, or what new piece would unlock more outfit combinations. \
                Returns 2–3 specific, purchasable item suggestions ordered by how many owned items \
                they pair with.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "category": [
                        "type": "string",
                        "description": """
                            Optional specific category to focus on (e.g. 'Trousers', 'Jacket', 'Top', \
                            'Footwear'). If omitted, Claude picks the category with the most impact \
                            based on wardrobe gaps.
                            """
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "askUserQuestion",
            "description": """
                Call this whenever you would otherwise list options in prose. If your next \
                sentence would be "Are you thinking: A, B, or C?" or "Would you prefer X or Y?", \
                call this tool INSTEAD with those options. Never list choices in text. Provide 2–4 \
                short, mutually-exclusive options. The UI renders them as tappable buttons with a \
                built-in "Other" freeform field.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "question": [
                        "type": "string",
                        "description": "The question to ask. Phrase it clearly and end with a question mark."
                    ],
                    "options": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "2–4 short, mutually-exclusive option labels (1–5 words each)."
                    ],
                    "allow_other": [
                        "type": "boolean",
                        "description": "If true (default), the UI also shows an 'Other' button with a freeform text field."
                    ],
                    "multi_select": [
                        "type": "boolean",
                        "description": "If true, the user can pick multiple options before submitting. Default false (first tap submits)."
                    ]
                ],
                "required": ["question", "options"]
            ]
        ]
    ]
}
