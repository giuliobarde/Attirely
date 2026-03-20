import UIKit

enum ImageStorageError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save image to disk."
        }
    }
}

struct ImageStorageService {
    private static let clothingImagesDir = "clothing-images"
    private static let scanImagesDir = "scan-images"

    static func saveClothingImage(_ image: UIImage, id: UUID) throws -> String {
        try save(image, directory: clothingImagesDir, filename: "\(id.uuidString).jpg")
    }

    static func saveScanImage(_ image: UIImage, id: UUID) throws -> String {
        try save(image, directory: scanImagesDir, filename: "\(id.uuidString).jpg")
    }

    static func loadImage(relativePath: String) -> UIImage? {
        let url = documentsURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deleteImage(relativePath: String) {
        let url = documentsURL.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func save(_ image: UIImage, directory: String, filename: String) throws -> String {
        let dirURL = documentsURL.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw ImageStorageError.saveFailed
        }
        let fileURL = dirURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return "\(directory)/\(filename)"
    }
}
