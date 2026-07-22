import SwiftUI

/// Highlighted card at the top of the feed for appreciations waiting on the user.
struct AcceptPendingCard: View {
    let gratitude: Gratitude
    var onAccepted: (Gratitude) -> Void
    var onDeclined: (UUID) -> Void

    @Environment(AuthService.self) private var auth
    @State private var acting: Action?
    @State private var errorMessage: String?
    @State private var fullScreenImageURL: URL?
    @State private var loadedAuthor: Profile?

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

            Text(gratitude.message)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = gratitude.mediaURL, gratitude.mediaType?.hasPrefix("video") != true {
                Button { fullScreenImageURL = url } label: {
                    FlexiblePostImage(url: url, maxHeight: 280)
                }
                .buttonStyle(.plain)
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
                .disabled(acting != nil)

                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Text(acting == .accept ? "Accepting…" : "Accept")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle())
                .disabled(acting != nil)
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
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
        .task {
            guard authorProfile == nil else { return }
            loadedAuthor = try? await GratitudeService.profile(id: gratitude.authorId)
        }
    }

    private func respond(accept: Bool) async {
        guard let userId = auth.userId else { return }
        acting = accept ? .accept : .decline
        errorMessage = nil
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
            } else {
                onDeclined(gratitude.id)
            }
        } catch {
            errorMessage = error.localizedDescription
            acting = nil
        }
    }
}
