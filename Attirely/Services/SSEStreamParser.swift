import Foundation

struct SSEStreamParser {

    /// Parses a URLSession async byte stream into typed SSE events.
    static func parse(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Buffer raw bytes so multi-byte UTF-8 sequences (e.g. °, emoji) are
                // decoded correctly. Decoding byte-by-byte treats each byte as its own
                // scalar, corrupting any non-ASCII character (e.g. ° → Â°).
                var lineBuffer: [UInt8] = []
                var currentEventType = ""
                var currentData = ""

                func flushLine() {
                    // Strip trailing \r to handle \r\n line endings
                    if lineBuffer.last == UInt8(ascii: "\r") {
                        lineBuffer.removeLast()
                    }
                    if let line = String(bytes: lineBuffer, encoding: .utf8) {
                        processLine(
                            line,
                            eventType: &currentEventType,
                            data: &currentData,
                            continuation: continuation
                        )
                    }
                    lineBuffer = []
                }

                do {
                    for try await byte in bytes {
                        if Task.isCancelled { break }

                        if byte == UInt8(ascii: "\n") {
                            flushLine()
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    // Process any remaining data in the buffer
                    if !lineBuffer.isEmpty {
                        flushLine()
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func processLine(
        _ line: String,
        eventType: inout String,
        data: inout String,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) {
        if line.hasPrefix("event: ") {
            eventType = String(line.dropFirst(7))
        } else if line.hasPrefix("data: ") {
            data = String(line.dropFirst(6))
        } else if line.isEmpty {
            // Blank line = event boundary — dispatch if we have data
            if !data.isEmpty {
                if let event = parseEvent(type: eventType, data: data) {
                    if case .error(let info) = event {
                        if info.contains("overloaded") {
                            continuation.finish(throwing: AnthropicError.overloaded)
                        } else {
                            continuation.finish(throwing: AnthropicError.apiError(0, info))
                        }
                    } else {
                        continuation.yield(event)
                    }
                }
                data = ""
                eventType = ""
            }
        }
        // Ignore other lines (comments starting with ":", etc.)
    }

    private static func parseEvent(type: String, data: String) -> SSEEvent? {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let payloadType = json["type"] as? String
        else { return nil }

        switch payloadType {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any],
                  let blockType = block["type"] as? String
            else { return nil }

            if blockType == "tool_use",
               let id = block["id"] as? String,
               let name = block["name"] as? String {
                return .toolUseStart(index: index, id: id, name: name)
            }
            // Text block starts don't carry meaningful data
            return nil

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String
            else { return nil }

            if deltaType == "text_delta", let text = delta["text"] as? String {
                return .textDelta(index: index, text: text)
            } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                return .toolUseInputDelta(index: index, partialJSON: partial)
            }
            return nil

        case "content_block_stop":
            guard let index = json["index"] as? Int else { return nil }
            return .contentBlockStop(index: index)

        case "message_delta":
            let delta = json["delta"] as? [String: Any]
            let stopReason = delta?["stop_reason"] as? String
            return .messageDelta(stopReason: stopReason)

        case "message_stop":
            return .messageStop

        case "error":
            let errorObj = json["error"] as? [String: Any]
            let errorType = errorObj?["type"] as? String ?? ""
            let message = errorObj?["message"] as? String ?? "Unknown streaming error"
            return .error(errorType.isEmpty ? message : "\(errorType):\(message)")

        default:
            // message_start, ping, etc. — ignore
            return nil
        }
    }
}
