import Foundation

/// Moves a Share Extension payload into ComposeLaunchBridge.
enum ComposeShareHandoff {
    /// Prefer an App Group share payload; otherwise open blank compose.
    @MainActor
    static func queuePendingShareOrBlank() {
        if applyPendingShare() { return }
        ComposeLaunchBridge.shared.queue()
    }

    /// If a share is waiting (e.g. user signed in after opening the URL), queue it.
    @MainActor
    @discardableResult
    static func applyPendingShare() -> Bool {
        guard let payload = ComposeShareStore.consume() else { return false }
        ComposeLaunchBridge.shared.queue(
            recipientName: payload.recipientName,
            message: payload.message,
            imageFileName: payload.imageFileName
        )
        return true
    }
}
