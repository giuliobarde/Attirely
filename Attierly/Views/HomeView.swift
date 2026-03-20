import SwiftUI
import PhotosUI
import SwiftData

struct HomeView: View {
    @State private var viewModel = ScanViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanSession.date, order: .reverse) private var recentSessions: [ScanSession]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)

                    Text("Attierly")
                        .font(.largeTitle.bold())

                    Text("Identify clothing with AI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            viewModel.showingCamera = true
                        } label: {
                            Label("Scan Clothes", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images
                    ) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)

                Spacer()

                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Scans")
                            .font(.headline)
                            .padding(.horizontal)

                        List(recentSessions) { session in
                            HStack(spacing: 12) {
                                if let image = ImageStorageService.loadImage(relativePath: session.imagePath) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 50, height: 50)
                                }

                                VStack(alignment: .leading) {
                                    Text("\(session.items.count) item\(session.items.count == 1 ? "" : "s") detected")
                                        .font(.subheadline.weight(.medium))
                                    Text(session.items.map(\.type).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 200)
                    }
                }
            }
            .navigationTitle("")
            .fullScreenCover(isPresented: $viewModel.showingCamera) {
                ImagePicker(sourceType: .camera) { image in
                    viewModel.analyzeImage(image)
                }
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $viewModel.showingResults) {
                ResultsView(viewModel: viewModel)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.analyzeImage(image)
                    }
                }
                selectedPhotoItem = nil
            }
            .onAppear {
                viewModel.modelContext = modelContext
            }
        }
    }
}
