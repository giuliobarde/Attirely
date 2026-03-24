import SwiftUI
import SwiftData

struct AgentMessageBubble: View {
    let message: ChatMessage
    let onSaveOutfit: (Outfit) -> Void
    let onItemTap: (ClothingItem) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 48)
                userBubble
            } else {
                assistantContent
                Spacer(minLength: 48)
            }
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        Text(message.text ?? "")
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.champagne)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Assistant Content

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Text
            if message.isStreaming && message.text == nil {
                streamingIndicator
            } else if let text = message.text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
            }

            // Outfit cards
            ForEach(message.outfits) { outfit in
                VStack(alignment: .leading, spacing: 8) {
                    OutfitRowCard(outfit: outfit) { }

                    // Wardrobe gap notes
                    if !outfit.wardrobeGapsDecoded.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(outfit.wardrobeGapsDecoded, id: \.self) { gap in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "lightbulb.max")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(gap)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }

                    if !isSaved(outfit) {
                        Button {
                            onSaveOutfit(outfit)
                        } label: {
                            Label("Save Outfit", systemImage: "square.and.arrow.down")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Theme.champagne)
                    } else {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.stone)
                    }
                }
            }

            // Wardrobe items
            if !message.wardrobeItems.isEmpty {
                wardrobeItemList
            }

            // Insight note
            if let note = message.insightNote {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.champagne)
                    Text("Noted: \(note)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .italic()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.champagne.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.stone)
                    .frame(width: 6, height: 6)
                    .opacity(0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: message.isStreaming
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Wardrobe Item List

    private var wardrobeItemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Found \(message.wardrobeItems.count) item\(message.wardrobeItems.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            ForEach(message.wardrobeItems) { item in
                Button {
                    onItemTap(item)
                } label: {
                    HStack(spacing: 10) {
                        if let path = item.sourceImagePath,
                           let image = ImageStorageService.loadImage(relativePath: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.placeholderFill)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Circle()
                                        .fill(ColorMapping.color(for: item.primaryColor))
                                        .frame(width: 16, height: 16)
                                }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.type)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.primaryText)
                            Text("\(item.category) · \(item.primaryColor)")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }

                        Spacer()

                        Text(item.formality)
                            .themeTag()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func isSaved(_ outfit: Outfit) -> Bool {
        outfit.modelContext != nil
    }
}
