import SwiftUI

/// Review + accept/decline for a pending appreciation.
/// Used from claim links and from notification taps that open a pending post.
struct PendingAppreciationReviewView: View {
    @State var gratitude: Gratitude
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var acting: Action?
    @State private var errorMessage: String?
    @State private var outcome: Outcome = .review
    /// Fallback when the embed didn't include author (still navigate by id).
    @State private var loadedAuthor: Profile?

    private enum Action { case accept, decline }
    private enum Outcome {
        case review
        case accepted(Gratitude)
        case declined
    }

    private var authorProfile: Profile? { gratitude.author ?? loadedAuthor }

    var body: some View {
        Group {
            switch outcome {
            case .review:
                reviewContent
            case .accepted(let accepted):
                GratitudeDetailView(gratitude: accepted)
            case .declined:
                declinedContent
            }
        }
        .background(Theme.background)
        .navigationTitle(outcomeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await linkRecipientIfNeeded()
            await loadAuthorIfNeeded()
        }
    }

    private var outcomeTitle: String {
        switch outcome {
        case .review: "Respond"
        case .accepted: "Appreciation"
        case .declined: "Declined"
        }
    }

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Someone appreciates you")
                    .font(Theme.display(26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Review and accept this appreciation shared for you.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: 14) {
                    ProfilePersonLink(profile: authorProfile, size: 48) {
                        if let date = gratitude.displayDate {
                            Text(date, format: .relative(presentation: .named))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    LinkifiedText(
                        text: gratitude.message,
                        font: Theme.display(18, weight: .regular),
                        foreground: Theme.textPrimary
                    )
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                    if let url = gratitude.mediaURL, gratitude.mediaType?.hasPrefix("video") != true {
                        FlexiblePostImage(url: url, maxHeight: 420)
                    }
                }
                .padding(18)
                .card()
                .softNoteReveal(delay: 0.05)

                AppreciationVisibilityNote(visibility: gratitude.visibility)
                    .softNoteReveal(delay: 0.12)

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
            .padding(.bottom, 96)
        }
        .onAppear { WarmHaptics.received() }
    }

    private var declinedContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.coral)
            Text("Declined")
                .font(Theme.display(22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("You declined this appreciation.")
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

    private func linkRecipientIfNeeded() async {
        guard let userId = auth.userId else { return }
        guard gratitude.recipientId != userId, let token = gratitude.claimToken else { return }
        try? await GratitudeService.assignClaimRecipient(
            gratitudeId: gratitude.id,
            claimToken: token,
            recipientId: userId,
            authorId: gratitude.authorId
        )
    }

    private func loadAuthorIfNeeded() async {
        guard authorProfile == nil else { return }
        loadedAuthor = try? await GratitudeService.profile(id: gratitude.authorId)
    }

    private func respond(_ action: Action) async {
        guard let userId = auth.userId else { return }
        acting = action
        errorMessage = nil
        do {
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
                accept: action == .accept
            )
            gratitude = updated
            if action == .accept {
                WarmHaptics.received()
            }
            withAnimation(Motion.note) {
                outcome = action == .accept ? .accepted(updated) : .declined
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        acting = nil
    }
}

/// Recipient flow for `https://openthanks.com/claim/{token}`.
struct ClaimAppreciationView: View {
    let token: UUID
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var gratitude: Gratitude?
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case ready
        case missing
        case alreadyProcessed
        case ownAppreciation
        case needsSignIn
    }

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
                case .ready:
                    if let gratitude {
                        PendingAppreciationReviewView(gratitude: gratitude)
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
                try? await GratitudeService.assignClaimRecipient(
                    gratitudeId: loaded.id,
                    claimToken: token,
                    recipientId: userId,
                    authorId: loaded.authorId
                )
            }

            phase = .ready
        } catch {
            if !error.isCancellation {
                phase = .missing
            }
        }
    }
}
