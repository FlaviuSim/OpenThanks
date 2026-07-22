import Foundation

/// What the user shared into OpenThanks — drives the prompt copy.
enum ComposeShareKind: String, Codable, Equatable {
    case contact
    case photo
    case calendar
    case url
    case text
    case unknown
}

/// Payload written by the Share Extension; consumed by the main app into compose.
struct ComposeSharePayload: Codable, Equatable {
    var kind: ComposeShareKind
    /// Short headline shown in the extension UI (and useful for analytics later).
    var promptTitle: String
    var recipientName: String?
    var message: String?
    var sourceURL: String?
    /// Relative filename under App Group `ShareInbox/`.
    var imageFileName: String?
    var createdAt: Date

    static func make(
        kind: ComposeShareKind,
        promptTitle: String,
        recipientName: String? = nil,
        message: String? = nil,
        sourceURL: String? = nil,
        imageFileName: String? = nil
    ) -> ComposeSharePayload {
        ComposeSharePayload(
            kind: kind,
            promptTitle: promptTitle,
            recipientName: trimmed(recipientName),
            message: trimmed(message),
            sourceURL: trimmed(sourceURL),
            imageFileName: trimmed(imageFileName),
            createdAt: .now
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

enum ComposeShareStore {
    private static let key = "composeSharePayload.v1"

    static func save(_ payload: ComposeSharePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func peek() -> ComposeSharePayload? {
        guard let data = AppGroup.defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode(ComposeSharePayload.self, from: data)
        else { return nil }
        // Ignore stale handoffs (e.g. user cancelled before opening the app).
        if payload.createdAt.addingTimeInterval(15 * 60) < Date() {
            clear()
            return nil
        }
        return payload
    }

    @discardableResult
    static func consume() -> ComposeSharePayload? {
        let payload = peek()
        clear()
        return payload
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }

    static func writeImage(_ data: Data, preferredExtension: String = "jpg") -> String? {
        guard let dir = AppGroup.shareImagesDirectory else { return nil }
        let name = "share-\(UUID().uuidString).\(preferredExtension)"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func imageURL(fileName: String) -> URL? {
        AppGroup.shareImagesDirectory?.appendingPathComponent(fileName)
    }

    static func readImageData(fileName: String) -> Data? {
        guard let url = imageURL(fileName: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func removeImage(fileName: String) {
        guard let url = imageURL(fileName: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
