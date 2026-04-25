import Foundation

// Lightweight in-process telemetry for Athena, the style agent. Counters live for the lifetime
// of the app process and are logged on each event so they show up in Xcode's console
// without needing a remote sink. Replace with proper analytics later if needed.
@MainActor
enum AgentTelemetry {

    private static var toolCallCounts: [String: Int] = [:]
    private static var unknownAliasCount: Int = 0
    private static var fuzzyFallbackCount: Int = 0
    private static var duplicateQuestionCount: Int = 0
    private static var prunedPendingOutfitsCount: Int = 0
    private static var malformedToolJSONCount: Int = 0

    // MARK: - Recording

    static func recordToolCall(_ name: String) {
        toolCallCounts[name, default: 0] += 1
        log("tool=\(name) total=\(toolCallCounts[name]!)")
    }

    // Bumped when an agent tool input cites a 6-hex alias that doesn't resolve to any
    // wardrobe item. High rate suggests the model is hallucinating IDs.
    static func recordUnknownAlias(_ alias: String, tool: String) {
        unknownAliasCount += 1
        log("unknownAlias tool=\(tool) alias=\(alias) total=\(unknownAliasCount)")
    }

    // Bumped when the description fallback path (free-form *_items / outfit_name) is
    // used after the alias path didn't match anything. High rate suggests the model
    // isn't reading aliases off tool results.
    static func recordFuzzyFallback(_ tool: String) {
        fuzzyFallbackCount += 1
        log("fuzzyFallback tool=\(tool) total=\(fuzzyFallbackCount)")
    }

    static func recordDuplicateQuestion() {
        duplicateQuestionCount += 1
        log("duplicateQuestion total=\(duplicateQuestionCount)")
    }

    static func recordPrunedPendingOutfits(_ count: Int) {
        prunedPendingOutfitsCount += count
        log("prunedPendingOutfits dropped=\(count) total=\(prunedPendingOutfitsCount)")
    }

    static func recordMalformedToolJSON(name: String, raw: String) {
        malformedToolJSONCount += 1
        // Truncate raw payload so logs stay readable on long inputs.
        let preview = raw.count > 240 ? raw.prefix(240) + "…" : Substring(raw)
        log("malformedToolJSON tool=\(name) total=\(malformedToolJSONCount) raw=\"\(preview)\"")
    }

    // MARK: - Snapshot (for ad-hoc debugging from a breakpoint)

    static func snapshot() -> String {
        let tools = toolCallCounts
            .sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        return """
        AgentTelemetry snapshot:
          tools: { \(tools) }
          unknownAlias: \(unknownAliasCount)
          fuzzyFallback: \(fuzzyFallbackCount)
          duplicateQuestion: \(duplicateQuestionCount)
          prunedPendingOutfits: \(prunedPendingOutfitsCount)
          malformedToolJSON: \(malformedToolJSONCount)
        """
    }

    private static func log(_ msg: String) {
        print("[AgentTelemetry] \(msg)")
    }
}
