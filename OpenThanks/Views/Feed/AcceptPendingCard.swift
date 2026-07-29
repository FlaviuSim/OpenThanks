import SwiftUI

/// Highlighted card at the top of the feed for appreciations waiting on the user.
struct AcceptPendingCard: View {
    let gratitude: Gratitude
    var onAccepted: (Gratitude) -> Void
    var onDeclined: (UUID) -> Void
    /// Called when an optimistic accept/decline failed so the parent can restore the card.
    var onFailed: (Gratitude) -> Void = { _ in }

    @Environment(AuthService.self) private var auth
    @State private var acting: Action?
    @State private var errorMessage: String?
    @State private var fullScreenImageURL: URL?
    @State private var loadedAuthor: Profile?
    /// Prevents double-tap from starting two accept tasks (second failure can resurrect the card).
    @State private var didSubmit = false

    private enum Action { case accept, decline }

    private var authorProfile: Profile? { gratitude.author ?? loadedAuthor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.coral)
                Text("Needs your acceptance")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Spacer()
            }

            ProfilePersonLink(
                profile: authorProfile,
                size: 40,
                nameFont: Theme.body(15, weight: .semibold)
            ) {
                Text("wrote you an appreciation")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            LinkifiedText(
                text: gratitude.message,
                font: Theme.body(15),
                foreground: Theme.textPrimary
            )
            .fixedSize(horizontal: false, vertical: true)

            if let url = gratitude.mediaURL {
                let isVideo = gratitude.mediaType?.lowercased().hasPrefix("video") == true
                if isVideo {
                    FlexiblePostMedia(url: url, mediaType: gratitude.mediaType, maxHeight: 280)
                } else {
                    Button { fullScreenImageURL = url } label: {
                        FlexiblePostImage(url: url, maxHeight: 280)
                    }
                    .buttonStyle(.plain)
                }
            }

            AppreciationVisibilityNote(visibility: gratitude.visibility)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(12))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await respond(accept: false) }
                } label: {
                    Text(acting == .decline ? "Declining…" : "Decline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .disabled(acting != nil || didSubmit)

                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Text(acting == .accept ? "Accepting…" : "Accept")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle())
                .disabled(acting != nil || didSubmit)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.coral.opacity(0.45), lineWidth: 1.5)
                )
        )
        .softNoteReveal()
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
        .task {
            guard authorProfile == nil else { return }
            loadedAuthor = try? await GratitudeService.profile(id: gratitude.authorId)
        }
    }

    private func respond(accept: Bool) async {
        guard !didSubmit else { return }
        guard let userId = auth.userId else { return }
        didSubmit = true
        acting = accept ? .accept : .decline
        errorMessage = nil

        // Remove the card immediately so a slow network (or a feed refresh race)
        // can't leave the UI stuck on "Accepting…" / bring the card back mid-flight.
        if accept {
            var optimistic = gratitude
            optimistic.status = .accepted
            Analytics.capture("appreciation_accepted")
            onAccepted(optimistic)
        } else {
            Analytics.capture("appreciation_declined")
            onDeclined(gratitude.id)
        }

        do {
            // Ensure we're attached as recipient when match was by email/phone.
            if gratitude.recipientId != userId, let token = gratitude.claimToken {
                try? await GratitudeService.assignClaimRecipient(
                    gratitudeId: gratitude.id,
                    claimToken: token,
                    recipientId: userId,
                    authorId: gratitude.authorId
                )
            }
            let updated = try await GratitudeService.respondToClaim(
                gratitudeId: gratitude.id,
                recipientId: userId,
                accept: accept
            )
            if accept {
                onAccepted(updated)
            }
            acting = nil
        } catch is CancellationError {
            // Unstructured Task can cancel after the card is removed — don't resurrect it.
            acting = nil
        } catch {
            // Already accepted/declined (e.g. double-submit) — keep it gone.
            if Self.isAlreadyResolvedError(error) {
                if accept {
                    var resolved = gratitude
                    resolved.status = .accepted
                    onAccepted(resolved)
                } else {
                    onDeclined(gratitude.id)
                }
                acting = nil
                return
            }
            didSubmit = false
            acting = nil
            errorMessage = error.localizedDescription
            onFailed(gratitude)
        }
    }

    private static func isAlreadyResolvedError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("already")
            || text.contains("no rows")
            || text.contains("0 rows")
            || text.contains("not found")
            || text.contains("processed")
    }
}
