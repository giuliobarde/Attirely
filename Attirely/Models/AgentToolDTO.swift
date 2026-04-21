import Foundation

// MARK: - Tool Names

enum AgentToolName: String {
    case generateOutfit
    case searchWardrobe
    case searchOutfits
    case updateStyleInsight
    case editOutfit
    case suggestPurchases
    case askUserQuestion
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
    // Free-form descriptions — fuzzy-matched. Fallback when aliases haven't been seen.
    let mustIncludeItems: [String]
    // 6-hex aliases (or full UUIDs). Deterministic — preferred path.
    let mustIncludeItemIDs: [String]

    init(from json: [String: Any]) {
        self.occasion = json["occasion"] as? String
        self.constraints = json["constraints"] as? String
        self.mustIncludeItems = (json["must_include_items"] as? [String]) ?? []
        self.mustIncludeItemIDs = (json["must_include_item_ids"] as? [String]) ?? []
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
    let outfitName: String?
    let outfitID: String?
    let removeItems: [String]
    let addItems: [String]
    let removeItemIDs: [String]
    let addItemIDs: [String]
    let newName: String?
    let newOccasion: String?

    init(from json: [String: Any]) {
        let rawName = json["outfit_name"] as? String
        self.outfitName = (rawName?.isEmpty == false) ? rawName : nil
        self.outfitID = json["outfit_id"] as? String
        self.removeItems = (json["remove_items"] as? [String]) ?? []
        self.addItems = (json["add_items"] as? [String]) ?? []
        self.removeItemIDs = (json["remove_item_ids"] as? [String]) ?? []
        self.addItemIDs = (json["add_item_ids"] as? [String]) ?? []
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

struct AskUserQuestionInput {
    let question: String
    let options: [String]
    let allowsOther: Bool
    let multiSelect: Bool

    init(from json: [String: Any]) {
        self.question = (json["question"] as? String) ?? ""
        let rawOptions = (json["options"] as? [String]) ?? []
        self.options = Array(rawOptions.prefix(4))
        self.allowsOther = (json["allow_other"] as? Bool) ?? true
        self.multiSelect = (json["multi_select"] as? Bool) ?? false
    }
}

// MARK: - Agent Turn Result

struct AgentTurn: @unchecked Sendable {
    let assistantText: String?
    let toolCalls: [ToolUseBlock]
    let rawAssistantContent: [[String: Any]]
    let stopReason: String
}
