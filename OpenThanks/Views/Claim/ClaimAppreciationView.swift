import SwiftUI

/// Recipient flow for `https://openthanks.com/claim/{token}`.
struct ClaimAppreciationView: View {
    let token: UUID
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var gratitude: Gratitude?
    @State private var phase: Phase = .loading
    @State private var acting: Action?
    @State private var errorMessage: String?

    private enum Phase {
        case loading
        case ready
        case missing
        case alreadyProcessed
        case ownAppreciation
        case needsSignIn
        case accepted(Gratitude)
        case declined
    }

    private enum Action { case accept, decline }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView().tint(Theme.coral)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .needsSignIn:
                    messageState(
                        title: "Sign in to claim",
                        body: "Open this link again after you sign in to accept the appreciation.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                case .missing:
                    messageState(
                        title: "Appreciation not found",
                        body: "This link is invalid or the appreciation is no longer available.",
                        systemImage: "exclamationmark.triangle"
                    )
                case .alreadyProcessed:
                    if let gratitude, gratitude.status == .accepted {
                        GratitudeDetailView(gratitude: gratitude)
                    } else {
                        messageState(
                            title: "Already processed",
                            body: "This appreciation has already been accepted or declined.",
                            systemImage: "heart"
                        )
                    }
                case .ownAppreciation:
                    messageState(
                        title: "This is your appreciation",
                        body: "Only the recipient can accept it. Share the claim link with them.",
                        systemImage: "paperplane"
                    )
                case .declined:
                    messageState(
                        title: "Declined",
                        body: "You declined this appreciation.",
                        systemImage: "xmark.circle"
                    )
                case .accepted(let accepted):
                    GratitudeDetailView(gratitude: accepted)
                case .ready:
                    if let gratitude {
                        claimContent(gratitude)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .appDestinations()
        }
        .task { await load() }
        .onChange(of: auth.userId) { _, userId in
            if userId != nil, case .needsSignIn = phase {
                Task { await load() }
            }
        }
        .syncAppAppearance()
    }

    private func claimContent(_ gratitude: Gratitude) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Someone appreciates you")
                    .font(Theme.display(26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Review and accept this appreciation shared for you.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AvatarView(profile: gratitude.author, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gratitude.author?.displayName ?? "Someone")
                                .font(Theme.body(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if let date = gratitude.createdAt {
                                Text(date, format: .relative(presentation: .named))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }

                    Text(gratitude.message)
                        .font(Theme.display(18, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = gratitude.mediaURL, gratitude.mediaType?.hasPrefix("video") != true {
                        FlexiblePostImage(url: url, maxHeight: 420)
                    }
                }
                .padding(18)
                .card()

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(13))
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await respond(.decline) }
                    } label: {
                        Text(acting == .decline ? "Declining…" : "Decline")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .disabled(acting != nil)

                    Button {
                        Task { await respond(.accept) }
                    } label: {
                        Text(acting == .accept ? "Accepting…" : "Accept")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle())
                    .disabled(acting != nil)
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }

    private func messageState(title: String, body: String, systemImage: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(Theme.coral)
            Text(title)
                .font(Theme.display(22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(CTAButtonStyle())
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard auth.userId != nil else {
            phase = .needsSignIn
            return
        }

        do {
            let loaded = try await GratitudeService.gratitude(claimToken: token)
            gratitude = loaded

            if loaded.authorId == auth.userId {
                phase = .ownAppreciation
                return
            }

            if loaded.status != .pending {
                phase = .alreadyProcessed
                return
            }

            if let userId = auth.userId, loaded.recipientId != userId {
                try? await GratitudeService.assignClaimRecipient(gratitudeId: loaded.id,
                                                                claimToken: token,
                                                                recipientId: userId)
            }

            phase = .ready
        } catch {
            if !error.isCancellation {
                phase = .missing
            }
        }
    }

    private func respond(_ action: Action) async {
        guard let gratitude, let userId = auth.userId else { return }
        acting = action
        errorMessage = nil
        do {
            let updated = try await GratitudeService.respondToClaim(
                gratitudeId: gratitude.id,
                recipientId: userId,
                accept: action == .accept
            )
            self.gratitude = updated
            phase = action == .accept ? .accepted(updated) : .declined
        } catch {
            errorMessage = error.localizedDescription
        }
        acting = nil
    }
}
