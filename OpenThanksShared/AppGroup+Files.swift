import Foundation

extension AppGroup {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var shareImagesDirectory: URL? {
        guard let root = containerURL else { return nil }
        let dir = root.appendingPathComponent("ShareInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
