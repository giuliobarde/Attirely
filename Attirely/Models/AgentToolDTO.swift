import Foundation

// MARK: - Tool Names

enum AgentToolName: String {
    case generateOutfit
    case searchWardrobe
    case updateStyleInsight
}

// MARK: - Parsed Tool Call (from Claude response)

struct ToolUseBlock: @unchecked Sendable {
    let toolUseID: String
    let name: AgentToolName
    let inputJSON: [String: Any]

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let nameStr = dict["name"] as? String,
              let name = AgentToolName(rawValue: nameStr),
              let input = dict["input"] as? [String: Any]
        else { return nil }

        self.toolUseID = id
        self.name = name
        self.inputJSON = input
    }
}

// MARK: - Typed Tool Inputs

struct GenerateOutfitInput {
    let occasion: String?
    let constraints: String?

    init(from json: [String: Any]) {
        self.occasion = json["occasion"] as? String
        self.constraints = json["constraints"] as? String
    }
}

struct SearchWardrobeInput {
    let query: String

    init(from json: [String: Any]) {
        self.query = (json["query"] as? String) ?? ""
    }
}

struct UpdateStyleInsightInput {
    let insight: String
    let confidence: String

    init(from json: [String: Any]) {
        self.insight = (json["insight"] as? String) ?? ""
        self.confidence = (json["confidence"] as? String) ?? "medium"
    }
}

// MARK: - Agent Turn Result

struct AgentTurn: @unchecked Sendable {
    let assistantText: String?
    let toolCalls: [ToolUseBlock]
    let rawAssistantContent: [[String: Any]]
    let stopReason: String
}
