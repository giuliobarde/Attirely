import Foundation

// MARK: - SSE Event

enum SSEEvent {
    case textDelta(index: Int, text: String)
    case toolUseStart(index: Int, id: String, name: String)
    case toolUseInputDelta(index: Int, partialJSON: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?)
    case messageStop
}

// MARK: - Content Block Accumulator

struct ContentBlockAccumulator {

    private(set) var textParts: [Int: String] = [:]
    private(set) var pendingToolCalls: [Int: PendingToolCall] = [:]
    private(set) var stopReason: String?

    struct PendingToolCall {
        let id: String
        let name: String
        var jsonChunks: [String] = []
    }

    mutating func apply(_ event: SSEEvent) {
        switch event {
        case .textDelta(let index, let text):
            textParts[index, default: ""].append(text)

        case .toolUseStart(let index, let id, let name):
            pendingToolCalls[index] = PendingToolCall(id: id, name: name)

        case .toolUseInputDelta(let index, let partialJSON):
            pendingToolCalls[index]?.jsonChunks.append(partialJSON)

        case .contentBlockStop:
            break // Tool calls finalized on demand via finishedToolCalls()

        case .messageDelta(let reason):
            stopReason = reason

        case .messageStop:
            break
        }
    }

    var assembledText: String? {
        let sorted = textParts.sorted { $0.key < $1.key }
        let joined = sorted.map(\.value).joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    func finishedToolCalls() -> [ToolUseBlock] {
        pendingToolCalls.sorted { $0.key < $1.key }.compactMap { _, pending in
            let fullJSON = pending.jsonChunks.joined()
            let inputDict: [String: Any]
            if fullJSON.isEmpty {
                inputDict = [:]
            } else if let data = fullJSON.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                inputDict = parsed
            } else {
                inputDict = [:]
            }
            return ToolUseBlock(from: [
                "id": pending.id,
                "name": pending.name,
                "input": inputDict
            ])
        }
    }

    func rawAssistantContent() -> [[String: Any]] {
        var content: [[String: Any]] = []

        // Gather all block indices and sort them
        let textIndices = Set(textParts.keys)
        let toolIndices = Set(pendingToolCalls.keys)
        let allIndices = textIndices.union(toolIndices).sorted()

        for index in allIndices {
            if let text = textParts[index] {
                content.append(["type": "text", "text": text])
            }
            if let tool = pendingToolCalls[index] {
                let fullJSON = tool.jsonChunks.joined()
                let inputDict: [String: Any]
                if fullJSON.isEmpty {
                    inputDict = [:]
                } else if let data = fullJSON.data(using: .utf8),
                          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    inputDict = parsed
                } else {
                    inputDict = [:]
                }
                content.append([
                    "type": "tool_use",
                    "id": tool.id,
                    "name": tool.name,
                    "input": inputDict
                ])
            }
        }

        return content
    }
}
