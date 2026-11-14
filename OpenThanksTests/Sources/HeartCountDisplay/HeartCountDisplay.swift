import Foundation

/// Mirrors `OpenThanks/Models/Models.swift` `HeartCountDisplay` for Linux `swift test`.
enum HeartCountDisplay {
    static func resolve(embedded: Int, live: Int = 0, viewerHasHearted: Bool = false) -> Int {
        max(embedded, live, viewerHasHearted ? 1 : 0)
    }
}
