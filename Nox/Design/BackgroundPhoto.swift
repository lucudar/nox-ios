import SwiftUI
import UIKit
import Observation

/// The custom background photo: downscaled, stored as JPEG in Application Support.
@MainActor
@Observable
final class BackgroundPhoto {
    private(set) var image: UIImage?

    private static var fileURL: URL { Persist.supportDirectory.appendingPathComponent("background.jpg") }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            image = UIImage(data: data)
        }
    }

    @discardableResult
    func set(_ data: Data) -> Bool {
        guard let source = UIImage(data: data) else { return false }
        let scaled = Self.downscale(source, maxSide: 1600)
        image = scaled
        if let jpeg = scaled.jpegData(compressionQuality: 0.86) {
            try? jpeg.write(to: Self.fileURL, options: .atomic)
        }
        return true
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let k = maxSide / longest
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
