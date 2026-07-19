import SwiftUI
import UIKit

/// In-memory image cache shared across avatars, feed media, and profile photos.
enum RemoteImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    static func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return nil }
            store(image, for: url)
            return image
        } catch {
            return nil
        }
    }
}

/// Drop-in replacement for `AsyncImage` with memory caching.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadURL: URL?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else if failed {
                placeholder()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }
        if loadURL == url, image != nil { return }
        loadURL = url
        failed = false
        if let cached = RemoteImageCache.image(for: url) {
            image = cached
            return
        }
        image = nil
        if let loaded = await RemoteImageCache.load(url) {
            image = loaded
        } else {
            failed = true
        }
    }
}
