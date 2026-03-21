import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var clothingItems: [ClothingItem]
    @Query private var outfits: [Outfit]

    @State private var viewModel = ProfileViewModel()
    @State private var selectedPhoto: PhotosPickerItem?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let profile {
                        profileHeader(profile)
                        preferencesSection(profile)
                        analyticsSection
                    }
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Profile")
            .onAppear {
                viewModel.ensureProfileExists(in: modelContext)
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
        }
        .themeCard()
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
