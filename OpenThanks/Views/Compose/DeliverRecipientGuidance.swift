import Foundation

/// Helper copy on the two-step deliver screen for guest vs member recipients.
enum DeliverRecipientGuidance {
    enum Kind: Equatable {
        case guestEmail
        case nameOnly(String)
        case member
    }

    static func line(for kind: Kind) -> String {
        switch kind {
        case .guestEmail:
            return "We’ll email this person the link"
        case .nameOnly(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmed.isEmpty ? "them" : trimmed
            return "Share the link with \(label) to accept"
        case .member:
            return "We’ll notify them — and you can share the link too"
        }
    }
}

/// Resolves the mailto `To:` address for the deliver Email button.
enum DeliverMailto {
    /// Prefer confirmed gratitude email, then draft field, then linked profile email.
    static func toAddress(
        confirmed: String?,
        draft: String?,
        profileEmail: String?
    ) -> String? {
        for candidate in [confirmed, draft, profileEmail] {
            guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  raw.contains("@")
            else { continue }
            return AuthService.normalizedEmail(raw)
        }
        return nil
    }
}

/// Compose share-screen `.id` — message/media only so recipient picks don’t remount.
enum ShareScreenIdentity {
    static func make(id: UUID, message: String, mediaUrl: String?) -> String {
        [id.uuidString, message, mediaUrl ?? ""].joined(separator: "|")
    }
}
