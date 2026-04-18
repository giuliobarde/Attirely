import Foundation

enum OutfitSimilarity {
    static func isDuplicate(candidate: [String], existing: [[String]]) -> Bool {
        let normalizedCandidate = candidate.sorted()
        guard !normalizedCandidate.isEmpty else { return false }
        return existing.contains { normalizedCandidate == $0.sorted() }
    }
}
