import Foundation
import UIKit

enum AnthropicError: LocalizedError {
    case invalidImage
    case networkError(Error)
    case apiError(Int, String)
    case decodingError(String)
    case emptyResults

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to process the image."
        case .networkError:
            return "Unable to connect. Check your internet connection."
        case .apiError:
            return "Something went wrong. Please try again."
        case .decodingError(let detail):
            return "Failed to parse the response: \(detail)"
        case .emptyResults:
            return "No clothing items detected. Try a clearer photo."
        }
    }
}

struct DuplicateResult {
    let existingItem: ClothingItem
    let classification: DuplicateClassification
    let explanation: String
}

enum DuplicateClassification: String, Codable {
    case sameItem = "same_item"
    case similar = "similar"
    case noMatch = "no_match"
}

struct AnthropicService {
    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-20250514"
    private static let maxTokens = 4096

    private static let analysisPrompt = """
    Analyze this image and identify every clothing item visible. For each item, return a JSON object with these fields:

    - type: specific item type (e.g., "Crew Neck T-Shirt", "Slim Jeans", "Chelsea Boots")
    - category: one of "Top", "Bottom", "Outerwear", "Footwear", "Accessory", "Full Body" (for dresses, jumpsuits)
    - primary_color: the dominant color (e.g., "Navy Blue", "Charcoal", "Cream")
    - secondary_color: accent or secondary color if present, otherwise null
    - pattern: one of "Solid", "Striped", "Plaid", "Floral", "Graphic", "Abstract", "Polka Dot", "Geometric", "Camo", "Other"
    - fabric_estimate: best guess at material (e.g., "Cotton", "Denim", "Wool", "Polyester", "Linen", "Leather", "Suede", "Silk", "Knit", "Fleece")
    - weight: one of "Lightweight", "Midweight", "Heavyweight"
    - formality: one of "Casual", "Smart Casual", "Business Casual", "Business", "Formal"
    - season: array of applicable seasons from ["Spring", "Summer", "Fall", "Winter"]
    - fit: one of "Slim", "Regular", "Relaxed", "Oversized", "Cropped", or null if not determinable
    - statement_level: one of "Low", "Medium", "High" — how much visual attention the piece draws
    - description: a brief one-sentence description of the item, noting any distinguishing features (graphics, logos, unique details, texture, visible wear, etc.)

    Return ONLY a valid JSON array of objects. No markdown, no explanation, no code fences. Just the raw JSON array.

    If no clothing items are detected, return an empty array: []
    """

    // MARK: - Clothing Analysis

    static func analyzeClothing(image: UIImage) async throws -> [ClothingItemDTO] {
        let apiKey = try ConfigManager.apiKey()

        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            throw AnthropicError.invalidImage
        }

        let base64Image = jpegData.base64EncodedString()

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": analysisPrompt
                        ]
                    ]
                ]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AnthropicError.decodingError("Invalid text encoding.")
        }

        let items: [ClothingItemDTO]
        do {
            items = try JSONDecoder().decode([ClothingItemDTO].self, from: jsonData)
        } catch {
            throw AnthropicError.decodingError(error.localizedDescription)
        }

        return items
    }

    // MARK: - Duplicate Detection

    static func checkDuplicates(
        scannedItem: ClothingItemDTO,
        candidates: [ClothingItem],
        image: UIImage
    ) async throws -> [DuplicateResult] {
        let apiKey = try ConfigManager.apiKey()

        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            throw AnthropicError.invalidImage
        }

        let base64Image = jpegData.base64EncodedString()

        var candidateDescriptions = ""
        for (index, candidate) in candidates.enumerated() {
            candidateDescriptions += """
            [\(index)] \(candidate.type) - \(candidate.category), \(candidate.primaryColor), \
            \(candidate.pattern), \(candidate.fabricEstimate). \(candidate.itemDescription)\n
            """
        }

        let prompt = """
        I just scanned a clothing item from this image. It was detected as:
        Type: \(scannedItem.type)
        Category: \(scannedItem.category)
        Color: \(scannedItem.primaryColor)
        Pattern: \(scannedItem.pattern)
        Fabric: \(scannedItem.fabricEstimate)
        Description: \(scannedItem.description)

        I have these existing items in my wardrobe that might be the same item:
        \(candidateDescriptions)

        For each existing item, determine if it is the SAME physical item as the scanned one, \
        just SIMILAR (same type but a different garment), or NO MATCH at all.

        Return a JSON array with one object per candidate:
        [{"index": 0, "classification": "same_item"|"similar"|"no_match", "explanation": "brief reason"}]

        Return ONLY valid JSON. No markdown, no explanation, no code fences.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let text = try await sendRequest(body: requestBody, apiKey: apiKey)
        let cleanedText = stripCodeFences(text)

        guard let jsonData = cleanedText.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else {
            return []
        }

        var results: [DuplicateResult] = []
        for entry in rawArray {
            guard let index = entry["index"] as? Int,
                  let classStr = entry["classification"] as? String,
                  let classification = DuplicateClassification(rawValue: classStr),
                  let explanation = entry["explanation"] as? String,
                  index < candidates.count
            else { continue }

            results.append(DuplicateResult(
                existingItem: candidates[index],
                classification: classification,
                explanation: explanation
            ))
        }

        return results
    }

    // MARK: - Helpers

    private static func sendRequest(body: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.apiError(httpResponse.statusCode, responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw AnthropicError.decodingError("Unexpected response structure.")
        }

        return text
    }

    private static func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
