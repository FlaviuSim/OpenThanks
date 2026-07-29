import SwiftUI
import UIKit
import ImageIO

/// In-memory image cache shared across avatars, feed media, and profile photos.
/// Images are decoded/downsampled to a pixel cap before caching so a few feed
/// photos can't blow past the budget.
enum RemoteImageCache {
    /// Default long-edge for feed/detail photos (~3× phone width at 3x).
    static let feedMaxPixelSize: CGFloat = 1_080
    /// Avatars are tiny on screen — keep decoded bitmaps small.
    static let avatarMaxPixelSize: CGFloat = 256
    /// Full-screen zoom still shouldn't hold multi‑megapixel originals.
    static let fullScreenMaxPixelSize: CGFloat = 1_600

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    private static let memoryWarningObserver: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            clear()
        }
    }()

    static func prepare() {
        _ = memoryWarningObserver
    }

    static func clear() {
        cache.removeAllObjects()
    }

    static func image(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, maxPixelSize))
    }

    static func store(_ image: UIImage, for url: URL, maxPixelSize: CGFloat) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key(url, maxPixelSize), cost: cost)
    }

    static func load(_ url: URL, maxPixelSize: CGFloat = feedMaxPixelSize) async -> UIImage? {
        prepare()
        if let cached = image(for: url, maxPixelSize: maxPixelSize) { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            let image = await Task.detached(priority: .userInitiated) {
                downsampledImage(data: data, maxPixelSize: maxPixelSize)
            }.value
            guard let image else { return nil }
            store(image, for: url, maxPixelSize: maxPixelSize)
            return image
        } catch {
            return nil
        }
    }

    private static func key(_ url: URL, _ maxPixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(maxPixelSize))" as NSString
    }

    /// Decode only a thumbnail via ImageIO — avoids allocating a full-res bitmap first.
    private static func downsampledImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let capped = max(1, maxPixelSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: capped,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            // Fallback if ImageIO can't thumbnail (rare formats).
            guard let image = UIImage(data: data) else { return nil }
            return image.downsampled(maxDimension: capped)
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Drop-in replacement for `AsyncImage` with memory caching + decode caps.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var maxPixelSize: CGFloat = RemoteImageCache.feedMaxPixelSize
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadKey: String?

    private var taskKey: String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)|\(Int(maxPixelSize))"
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: taskKey) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }
        if loadKey == taskKey, image != nil { return }
        loadKey = taskKey
        failed = false
        if let cached = RemoteImageCache.image(for: url, maxPixelSize: maxPixelSize) {
            image = cached
            return
        }
        image = nil
        if let loaded = await RemoteImageCache.load(url, maxPixelSize: maxPixelSize) {
            image = loaded
        } else {
            failed = true
        }
    }
}
