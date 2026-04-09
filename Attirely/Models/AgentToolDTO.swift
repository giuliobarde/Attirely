import Foundation

// MARK: - Tool Names

enum AgentToolName: String {
    case generateOutfit
    case searchWardrobe
    case searchOutfits
    case updateStyleInsight
    case editOutfit
    case suggestPurchases
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
    let mustIncludeItems: [String]

    init(from json: [String: Any]) {
        self.occasion = json["occasion"] as? String
        self.constraints = json["constraints"] as? String
        self.mustIncludeItems = (json["must_include_items"] as? [String]) ?? []
    }
}

struct SearchWardrobeInput {
    let query: String

    init(from json: [String: Any]) {
        self.query = (json["query"] as? String) ?? ""
    }
}

struct SearchOutfitsInput {
    let query: String?
    let tags: [String]

    init(from json: [String: Any]) {
        self.query = json["query"] as? String
        self.tags = (json["tags"] as? [String]) ?? []
    }
}

struct UpdateStyleInsightInput {
    let insight: String
    let confidence: String
    let category: String?
    let signal: String?

    init(from json: [String: Any]) {
        self.insight = (json["insight"] as? String) ?? ""
        self.confidence = (json["confidence"] as? String) ?? "medium"
        self.category = json["category"] as? String
        self.signal = json["signal"] as? String
    }
}

struct EditOutfitInput {
    let outfitName: String
    let removeItems: [String]
    let addItems: [String]
    let newName: String?
    let newOccasion: String?

    init(from json: [String: Any]) {
        self.outfitName = (json["outfit_name"] as? String) ?? ""
        self.removeItems = (json["remove_items"] as? [String]) ?? []
        self.addItems = (json["add_items"] as? [String]) ?? []
        self.newName = json["new_name"] as? String
        self.newOccasion = json["new_occasion"] as? String
    }
}

struct SuggestPurchasesInput {
    let category: String?

    init(from json: [String: Any]) {
        self.category = json["category"] as? String
    }
}

// MARK: - Agent Turn Result

struct AgentTurn: @unchecked Sendable {
    let assistantText: String?
    let toolCalls: [ToolUseBlock]
    let rawAssistantContent: [[String: Any]]
    let stopReason: String
}
