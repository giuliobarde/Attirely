import SwiftUI
import SwiftData

struct AgentView: View {
    @State private var viewModel = AgentViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.createdAt) private var wardrobeItems: [ClothingItem]
    @Query(sort: \Outfit.createdAt, order: .reverse) private var allOutfits: [Outfit]
    @Query private var profiles: [UserProfile]
    @Query private var styleSummaries: [StyleSummary]
    @Bindable var weatherViewModel: WeatherViewModel
    var styleViewModel: StyleViewModel

    @State private var showNewChatConfirmation = false
    @State private var selectedItem: ClothingItem?
    @FocusState private var isInputFocused: Bool

    private var activeProfile: UserProfile? { profiles.first }
    private var hasMessages: Bool { !viewModel.messages.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weatherChip

                if hasMessages {
                    chatScrollView
                } else {
                    starterScreen
                }
            }
            .background(Theme.screenBackground)
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .animation(.easeInOut(duration: 0.3), value: hasMessages)
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(hasMessages ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasMessages {
                        Button {
                            if viewModel.hasUnsavedOutfits {
                                showNewChatConfirmation = true
                            } else {
                                startNewChat()
                            }
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WeatherWidgetView(viewModel: weatherViewModel)
                }
            }
            .confirmationDialog(
                "Unsaved Outfits",
                isPresented: $showNewChatConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard & Start New", role: .destructive) {
                    startNewChat()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved outfit suggestions. Starting a new chat will discard them.")
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    ItemDetailView(item: item)
                }
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.weatherViewModel = weatherViewModel
            viewModel.userProfile = activeProfile
            viewModel.styleViewModel = styleViewModel
            viewModel.updateStyleContext(from: styleSummaries.first)
            viewModel.refreshWardrobe(items: wardrobeItems, outfits: allOutfits)
        }
        .onChange(of: wardrobeItems.count) {
            viewModel.refreshWardrobe(items: wardrobeItems, outfits: allOutfits)
        }
        .onChange(of: allOutfits.count) {
            viewModel.refreshWardrobe(items: wardrobeItems, outfits: allOutfits)
        }
    }

    // MARK: - Starter Screen

    private var starterScreen: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.stone)

                        Text("Style Agent")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.primaryText)

                        Text("Ask about your wardrobe, get outfit suggestions, or explore your style.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(spacing: 10) {
                        starterButton("What should I wear today?")
                        starterButton("Suggest a casual weekend outfit")
                        starterButton("What's missing from my wardrobe?")
                        starterButton("Show me my formal pieces")
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .transition(.opacity)
    }

    private func starterButton(_ text: String) -> some View {
        Button {
            viewModel.sendStarterMessage(text)
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chat Scroll View

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        AgentMessageBubble(
                            message: message,
                            onSaveOutfit: { outfit in
                                viewModel.saveOutfit(outfit)
                            },
                            onItemTap: { item in
                                selectedItem = item
                            },
                            itemsForOutfit: { outfit in
                                viewModel.displayItems(for: outfit)
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 80)
                .onTapGesture { isInputFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your style...", text: $viewModel.inputText, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 0.5)
                )
                .onSubmit {
                    guard canSend else { return }
                    viewModel.sendUserMessage()
                }

            Button {
                viewModel.sendUserMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Theme.champagne : Theme.stone)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Weather Chip

    @ViewBuilder
    private var weatherChip: some View {
        if let snapshot = weatherViewModel.snapshot {
            let unit = activeProfile?.temperatureUnit ?? .celsius
            HStack(spacing: 6) {
                Image(systemName: snapshot.current.conditionSymbol)
                    .font(.caption2)
                    .foregroundStyle(Theme.champagne)
                Text("\(TemperatureFormatter.format(snapshot.current.temperature, unit: unit)) · \(snapshot.current.conditionDescription)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                if let location = snapshot.locationName {
                    Text("· \(location)")
                        .font(.caption2)
                        .foregroundStyle(Theme.stone)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.cardFill)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.cardBorder, lineWidth: 0.5))
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }

    private func startNewChat() {
        viewModel.cancelCurrentTask()
        viewModel.clearConversation()
    }
}
