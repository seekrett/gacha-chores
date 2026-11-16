import UIKit

enum PhotoStore {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("proofs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func save(_ image: UIImage) -> String? {
        let resized = image.resized(maxDimension: 1600)
        guard let data = resized.jpegData(compressionQuality: 0.75) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: url(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: url(name).path)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
