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

    // MARK: - Tool Definitions

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "generateOutfit",
            "description": """
                Generate a complete outfit from the user's wardrobe based on current weather \
                and preferences. Call this when the user asks for outfit suggestions, asks what \
                to wear, or requests an outfit for a specific occasion. Returns a styled outfit \
                with reasoning.
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
                        "description": "Natural language description of what to find, e.g. 'blue tops', 'formal shoes', 'lightweight summer items', 'anything with stripes'."
                    ]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "updateStyleInsight",
            "description": """
                Capture a durable style preference signal expressed by the user in this \
                conversation. Use this ONLY when the user explicitly states a preference, \
                dislike, or self-knowledge about their style — not for inferred observations. \
                Examples: 'I hate wearing suits', 'I prefer oversized fits', 'navy is my go-to color'.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "insight": [
                        "type": "string",
                        "description": "The preference signal to record, written as a concise statement. E.g. 'Prefers oversized fits over slim cuts.'"
                    ],
                    "confidence": [
                        "type": "string",
                        "description": "How explicitly the user stated this preference.",
                        "enum": ["high", "medium", "low"]
                    ]
                ],
                "required": ["insight", "confidence"]
            ]
        ]
    ]
}
