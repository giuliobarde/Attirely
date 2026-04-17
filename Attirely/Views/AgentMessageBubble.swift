import SwiftUI
import SwiftData
import Combine

struct AgentMessageBubble: View {
    let message: ChatMessage
    let onSaveOutfit: (Outfit) -> Void
    let onItemTap: (ClothingItem) -> Void
    var itemsForOutfit: ((Outfit) -> [ClothingItem])? = nil
    var onBuildOutfitAround: ((String) -> Void)? = nil
    var onUpdateOriginal: ((Outfit) -> Void)? = nil
    var isCopyOfSavedOutfit: (Outfit) -> Bool = { _ in false }
    var onAnswerQuestion: ((UUID, AgentQuestionAnswer) -> Void)? = nil

    @State private var phraseIndex = 0
    @State private var isWardrobeListExpanded = false

    private let thinkingPhrases = [
        "Checking your wardrobe…",
        "Exploring outfit options…",
        "Thinking about combinations…",
        "Considering the weather…",
        "Looking through your style…",
        "Finding the right pieces…",
        "Pulling things together…",
    ]

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
                markdownText(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
            }

            // Outfit cards
            ForEach(message.outfits) { outfit in
                VStack(alignment: .leading, spacing: 8) {
                    OutfitRowCard(outfit: outfit, itemsOverride: itemsForOutfit?(outfit)) { }

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
                        if isCopyOfSavedOutfit(outfit), let onUpdateOriginal {
                            HStack(spacing: 14) {
                                Button {
                                    onUpdateOriginal(outfit)
                                } label: {
                                    Label("Update Original", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(Theme.champagne)

                                Button {
                                    onSaveOutfit(outfit)
                                } label: {
                                    Label("Save as New", systemImage: "square.and.arrow.down")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(Theme.champagne)
                            }
                        } else {
                            Button {
                                onSaveOutfit(outfit)
                            } label: {
                                Label("Save Outfit", systemImage: "square.and.arrow.down")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(Theme.champagne)
                        }
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

            // Purchase suggestions
            if !message.purchaseSuggestions.isEmpty {
                purchaseSuggestionList
            }

            // Agent question (multiple choice)
            if let question = message.question {
                if let answer = question.answer {
                    questionRecap(answer)
                } else {
                    AgentQuestionCard(question: question) { ans in
                        onAnswerQuestion?(question.id, ans)
                    }
                }
            }
        }
    }

    // MARK: - Agent Question Recap

    private func questionRecap(_ answer: AgentQuestionAnswer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.champagne)
            Text("You chose: \(answer.recap)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .italic()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.champagne.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Purchase Suggestions

    private var purchaseSuggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.purchaseSuggestions) { suggestion in
                purchaseSuggestionCard(suggestion)
            }
        }
    }

    private func purchaseSuggestionCard(_ suggestion: PurchaseSuggestionDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category + compatibility count
            HStack {
                Text(suggestion.category)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.pillActiveBg)
                    .foregroundStyle(Theme.pillActiveText)
                    .clipShape(Capsule())

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(Theme.champagne)
                    Text("Pairs with \(suggestion.wardrobeCompatibilityCount)")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            // Description
            Text(suggestion.description)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)

            // Style note
            Text(suggestion.styleNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            // Pairs with list
            if !suggestion.pairsWith.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Works with:")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(suggestion.pairsWith.prefix(4), id: \.self) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Theme.champagne.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(item)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }

            // Pipe-in button
            if let onBuildOutfitAround {
                Button {
                    onBuildOutfitAround(suggestion.description)
                } label: {
                    Label("Style an outfit around this", systemImage: "arrow.right.circle")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.champagne)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thinkingPhrases[phraseIndex % thinkingPhrases.count])
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .id(phraseIndex)
                .transition(.opacity)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.stone)
                        .frame(width: 4, height: 4)
                        .opacity(0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: message.isStreaming
                        )
                }
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
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                phraseIndex += 1
            }
        }
    }

    // MARK: - Wardrobe Item List

    private var wardrobeItemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isWardrobeListExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tshirt")
                        .font(.caption2)
                        .foregroundStyle(Theme.champagne)
                    Text("Found \(message.wardrobeItems.count) item\(message.wardrobeItems.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Image(systemName: isWardrobeListExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isWardrobeListExpanded {
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

    private func markdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}
