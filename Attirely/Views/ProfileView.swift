import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var clothingItems: [ClothingItem]
    @Query private var outfits: [Outfit]
    @Query private var styleSummaries: [StyleSummary]

    @State private var viewModel = ProfileViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    var styleViewModel: StyleViewModel

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let profile {
                        profileHeader(profile)
                        preferencesSection(profile)
                        styleComfortSection(profile)
                        styleSummarySection
                        analyticsSection
                    }
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Profile")
            .onAppear {
                viewModel.ensureProfileExists(in: modelContext)
                styleViewModel.modelContext = modelContext
            }
        }
    }

    // MARK: - Profile Header

    private func profileHeader(_ profile: UserProfile) -> some View {
        VStack(spacing: 12) {
            // Photo
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let path = profile.profileImagePath,
                   let image = ImageStorageService.loadImage(relativePath: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                } else {
                    Circle()
                        .fill(Theme.placeholderFill)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(Theme.secondaryText)
                        )
                        .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                }
            }
            .onChange(of: selectedPhoto) {
                Task {
                    if let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.updateProfilePhoto(image, profile: profile)
                    }
                }
            }

            // Name
            if viewModel.isEditingName {
                HStack(spacing: 8) {
                    TextField("Your name", text: $viewModel.editedName)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit {
                            viewModel.saveName(viewModel.editedName, profile: profile)
                        }
                    Button {
                        viewModel.saveName(viewModel.editedName, profile: profile)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.champagne)
                    }
                }
            } else {
                Button {
                    viewModel.editedName = profile.name
                    viewModel.isEditingName = true
                } label: {
                    HStack(spacing: 4) {
                        Text(profile.name.isEmpty ? "Add your name" : profile.name)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(profile.name.isEmpty ? Theme.secondaryText : Theme.primaryText)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            // Stats
            Text("\(clothingItems.count) items · \(outfits.count) outfits")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .themeCard()
    }

    // MARK: - Preferences

    private func preferencesSection(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)

            // Temperature unit
            VStack(alignment: .leading, spacing: 6) {
                Text("Temperature Unit")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Temperature", selection: Binding(
                    get: { profile.temperatureUnit },
                    set: { viewModel.updateTemperatureUnit($0, profile: profile) }
                )) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Theme
            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Theme", selection: Binding(
                    get: { profile.themePreference },
                    set: { viewModel.updateThemePreference($0, profile: profile) }
                )) {
                    ForEach(ThemePreference.allCases, id: \.self) { pref in
                        Text(pref.rawValue).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Location override
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Custom location", isOn: Binding(
                    get: { profile.isLocationOverrideEnabled },
                    set: { viewModel.toggleLocationOverride($0, profile: profile) }
                ))
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .tint(Theme.champagne)

                if profile.isLocationOverrideEnabled {
                    HStack(spacing: 8) {
                        TextField("City name", text: $viewModel.locationCityInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .onAppear {
                                viewModel.locationCityInput = profile.locationOverrideName ?? ""
                            }

                        Button {
                            viewModel.geocodeAndSaveLocation(profile: profile)
                        } label: {
                            if viewModel.isGeocodingLocation {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Save")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .disabled(viewModel.locationCityInput.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isGeocodingLocation)
                        .foregroundStyle(Theme.champagne)
                    }

                    if let savedCity = profile.locationOverrideName {
                        Text("Using weather for \(savedCity)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let error = viewModel.locationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if profile.locationOverrideName != nil {
                        Button("Clear location") {
                            viewModel.clearLocationOverride(profile: profile)
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            Divider()

            NavigationLink {
                TagManagementView()
            } label: {
                HStack {
                    Text("Manage Tags")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Divider()

            // Siri
            VStack(alignment: .leading, spacing: 8) {
                Text("Siri")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                Toggle("AI outfit generation", isOn: Binding(
                    get: { profile.isSiriAIGenerationEnabled },
                    set: { profile.isSiriAIGenerationEnabled = $0; profile.updatedAt = Date() }
                ))
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .tint(Theme.champagne)

                if profile.isSiriAIGenerationEnabled {
                    Text("When enabled, Siri may take 5–15 seconds to generate an outfit using AI if no pre-tagged outfits match.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Tag outfits with \"siri\" in the Outfits tab for instant Siri responses.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .themeCard()
    }

    // MARK: - Style & Comfort

    private func styleComfortSection(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Style & Comfort")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)

            // Cold sensitivity
            VStack(alignment: .leading, spacing: 6) {
                Text("Cold Sensitivity")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Cold Sensitivity", selection: Binding(
                    get: { profile.coldSensitivityEnum ?? .moderate },
                    set: { viewModel.updateColdSensitivity($0, profile: profile) }
                )) {
                    ForEach(ColdSensitivity.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Heat sensitivity
            VStack(alignment: .leading, spacing: 6) {
                Text("Heat Sensitivity")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Heat Sensitivity", selection: Binding(
                    get: { profile.heatSensitivityEnum ?? .moderate },
                    set: { viewModel.updateHeatSensitivity($0, profile: profile) }
                )) {
                    ForEach(HeatSensitivity.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Body temperature notes
            VStack(alignment: .leading, spacing: 6) {
                Text("Body Temperature Notes")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                TextField("e.g., legs run hot, hands always cold", text: Binding(
                    get: { profile.bodyTempNotes ?? "" },
                    set: { viewModel.updateBodyTempNotes($0, profile: profile) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            }

            Divider()

            // Layering preference
            VStack(alignment: .leading, spacing: 6) {
                Text("Layering Preference")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Layering", selection: Binding(
                    get: { profile.layeringPreferenceEnum ?? .happy },
                    set: { viewModel.updateLayeringPreference($0, profile: profile) }
                )) {
                    ForEach(LayeringPreference.allCases, id: \.self) { pref in
                        Text(pref.rawValue).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Style identity (multi-select tag grid)
            VStack(alignment: .leading, spacing: 8) {
                Text("Style Identity")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                let allStyles = ["Minimalist", "Streetwear", "Preppy", "Classic", "Bohemian",
                                 "Athletic", "Avant-Garde", "Vintage", "Smart Casual"]
                let selected = profile.selectedStylesArray

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(allStyles, id: \.self) { style in
                        Button {
                            viewModel.toggleStyle(style, profile: profile)
                        } label: {
                            Text(style)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selected.contains(style) ? Theme.pillActiveBg : Theme.pillDefaultBg
                                )
                                .foregroundStyle(
                                    selected.contains(style) ? Theme.champagne : Theme.pillDefaultText
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Comfort vs appearance
            VStack(alignment: .leading, spacing: 6) {
                Text("Comfort vs Appearance")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Comfort", selection: Binding(
                    get: { profile.comfortVsAppearanceEnum ?? .balanced },
                    set: { viewModel.updateComfortVsAppearance($0, profile: profile) }
                )) {
                    ForEach(ComfortVsAppearance.allCases, id: \.self) { pref in
                        Text(pref.rawValue).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Weather dressing approach
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather Dressing")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Picker("Weather Dressing", selection: Binding(
                    get: { profile.weatherDressingApproachEnum ?? .conditions },
                    set: { viewModel.updateWeatherDressingApproach($0, profile: profile) }
                )) {
                    ForEach(WeatherDressingApproach.allCases, id: \.self) { approach in
                        Text(approach.rawValue).tag(approach)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .themeCard()
    }

    // MARK: - Style Summary

    private var styleSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = styleSummaries.first, summary.isAIEnriched {
                aiEnrichedSummary(summary)
            } else {
                templateSummary
            }
        }
        .themeCard()
    }

    private func aiEnrichedSummary(_ summary: StyleSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Your Style Profile")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button(viewModel.isEditingStyleSummary ? "Done" : "Edit") {
                    if viewModel.isEditingStyleSummary {
                        viewModel.updateSummaryText(viewModel.editedStyleSummary)
                    } else {
                        viewModel.editedStyleSummary = summary.overallIdentity
                    }
                    viewModel.isEditingStyleSummary.toggle()
                }
                .font(.caption)
                .foregroundStyle(Theme.champagne)
            }

            // Overall identity
            if viewModel.isEditingStyleSummary {
                TextEditor(text: $viewModel.editedStyleSummary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Theme.placeholderFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(summary.overallIdentity)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
            }

            // Style mode cards
            let modes = summary.styleModesDecoded
            if !modes.isEmpty {
                ForEach(modes, id: \.name) { mode in
                    styleModeCard(mode)
                }
            }

            // Secondary sections
            if let temporal = summary.temporalNotes, !temporal.isEmpty {
                secondarySection(title: "Seasonal Patterns", text: temporal)
            }
            if let gaps = summary.gapObservations, !gaps.isEmpty {
                secondarySection(title: "Opportunities", text: gaps)
            }
            if let weather = summary.weatherBehavior, !weather.isEmpty {
                secondarySection(title: "Weather Style", text: weather)
            }

            // Tags
            HStack(spacing: 8) {
                if summary.isUserEdited {
                    Text("Edited by you")
                        .themeTag()
                }
                Text("AI Enhanced")
                    .themeTag()
            }

            // Footer
            Text("Last analyzed \(summary.lastAnalyzedAt.formatted(.relative(presentation: .named))) · Based on \(summary.itemCountAtLastAnalysis) items")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)

            // Re-analyze button
            Button {
                styleViewModel.analyzeStyle(
                    items: clothingItems,
                    outfits: outfits,
                    profile: profile,
                    force: true
                )
            } label: {
                if styleViewModel.isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Analyzing...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Re-analyze Style", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.themeSecondary)
            .disabled(styleViewModel.isAnalyzing)
        }
    }

    private func styleModeCard(_ mode: StyleModeDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mode.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(mode.formality)
                    .themeTag()
            }

            Text(mode.description)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            // Color palette swatches
            if !mode.colorPalette.isEmpty {
                HStack(spacing: 6) {
                    ForEach(mode.colorPalette, id: \.self) { colorName in
                        Circle()
                            .fill(ColorMapping.color(for: colorName))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.placeholderFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func secondarySection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.secondaryText)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.primaryText)
        }
    }

    private var templateSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Style Summary")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if styleSummaries.first != nil {
                    Button(viewModel.isEditingStyleSummary ? "Done" : "Edit") {
                        if viewModel.isEditingStyleSummary {
                            viewModel.updateSummaryText(viewModel.editedStyleSummary)
                        } else {
                            viewModel.editedStyleSummary = styleSummaries.first?.overallIdentity ?? ""
                        }
                        viewModel.isEditingStyleSummary.toggle()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.champagne)
                }
            }

            if let summary = styleSummaries.first {
                if viewModel.isEditingStyleSummary {
                    TextEditor(text: $viewModel.editedStyleSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Theme.placeholderFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(summary.overallIdentity)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                }

                if summary.isUserEdited {
                    Text("Edited by you")
                        .themeTag()
                }
            } else {
                Text("Fill out the style questionnaire above to generate your summary.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            // Progress toward AI analysis
            let itemCount = clothingItems.count
            ProgressView(value: Double(min(itemCount, 8)), total: 8)
                .tint(Theme.champagne)

            if itemCount >= 8 {
                Text("Ready for AI style analysis")
                    .font(.caption)
                    .foregroundStyle(Theme.champagne)
            } else {
                Text("\(itemCount)/8 items — add more to unlock AI style analysis")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            if styleViewModel.canAnalyze {
                Button {
                    styleViewModel.analyzeStyle(
                        items: clothingItems,
                        outfits: outfits,
                        profile: profile,
                        force: true
                    )
                } label: {
                    if styleViewModel.isAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Analyzing your style...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Analyze My Style", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.themePrimary)
                .disabled(styleViewModel.isAnalyzing)
            }

            if let error = styleViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Analytics

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wardrobe Analytics")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)
                .padding(.leading, 4)

            WardrobeAnalyticsView(items: clothingItems, viewModel: viewModel)
        }
    }
}
