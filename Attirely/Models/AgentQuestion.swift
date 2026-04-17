import Foundation

struct AgentQuestion: Identifiable, Equatable {
    let id: UUID
    let toolUseID: String
    let question: String
    let options: [String]
    let allowsOther: Bool
    let multiSelect: Bool
    var answer: AgentQuestionAnswer? = nil
}

struct AgentQuestionAnswer: Equatable {
    let selectedOptions: [String]
    let otherText: String?

    var recap: String {
        var parts = selectedOptions
        if let t = otherText, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: ", ")
    }
}
