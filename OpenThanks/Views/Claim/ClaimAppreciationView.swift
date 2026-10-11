import SwiftUI

/// Review + accept/decline for a pending appreciation.
/// Used from claim links and from notification taps that open a pending post.
struct PendingAppreciationReviewView: View {
    @State var gratitude: Gratitude
    /// Analytics `source` for `appreciation_accepted` / `appreciation_declined`.
    var analyticsSource: String = "claim"
    /// When set, called after a successful accept so the host can navigate to the
    /// accepted appreciation page (claim deep links redirect here).
    var onAccepted: ((Gratitude) -> Void)? = nil
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var acting: Action?
    @State private var errorMessage: String?
    @State private var showPrivateConfirm = false
    @State private var outcome: Outcome = .review
    /// Fallback when the embed didn't include author (still navigate by id).
    @State private var loadedAuthor: Profile?

    private enum Action { case accept, decline, acceptPrivate }
    private enum Outcome {
        case review
        case accepted(Gratitude)
        case declined
    }

    @State private var showCompose = false
    @State private var showPayItForward = false
    /// One `appreciation_viewed` per time this accept screen is created.
    @State private var didCaptureAppreciationView = false

    private var authorProfile: Profile? { gratitude.author ?? loadedAuthor }

    var body: some View {
        Group {
            switch outcome {
            case .review:
                reviewContent
            case .accepted(let accepted):
                // Fallback when the host doesn't redirect (e.g. in-place loaders).
                VStack(spacing: 0) {
                    if showPayItForward {
                        PayItForwardNudgeCard(
                            fromName: authorProfile?.fullName
                                ?? authorProfile?.displayName,
                            onThankSomeone: {
                                Analytics.capture(
                                    "pay_it_forward_tapped",
                                    [
                                        "source": "claim_accept",
                                        "parent_gratitude_id": gratitude.id.uuidString.lowercased(),
                                    ]
                                )
                                showCompose = true
                                AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                            },
                            onDismiss: {
                                withAnimation(Motion.note) {
                                    showPayItForward = false
                                }
                                AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    GratitudeDetailView(gratitude: accepted)
                }
            case .declined:
                declinedContent
            }
        }
        .background(Theme.background)
        .navigationTitle(outcomeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .composeCover(isPresented: $showCompose) {
            ComposeView(
                inspiredByGratitudeId: gratitude.id,
                inspiredByAuthorName: authorProfile?.fullName ?? authorProfile?.displayName,
                analyticsSource: "post_accept_pay_it_forward"
            )
        }
        .task {
            captureAppreciationViewIfNeeded()
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

                Text("OpenThanks is for real thank-yous — not ads or spam. Nothing posts publicly until you accept.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

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

                    if let url = gratitude.mediaURL {
                        FlexiblePostMedia(
                            url: url,
                            mediaType: gratitude.mediaType,
                            maxHeight: 420
                        )
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

                VStack(spacing: 8) {
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

                    if gratitude.senderMarkedPublic {
                        AcceptPrivatelyLink(isEnabled: acting == nil) {
                            errorMessage = nil
                            showPrivateConfirm = true
                        }
                    }
                }
            }
            .padding(20)
            .tabChromeBottomPadding()
            .readableWidth()
        }
        .onAppear { WarmHaptics.received() }
        .sheet(isPresented: $showPrivateConfirm) {
            AcceptPrivatelySheet(
                senderName: authorProfile?.fullName ?? authorProfile?.displayName,
                isWorking: acting == .accept || acting == .acceptPrivate,
                errorMessage: errorMessage,
                onKeepPrivate: { Task { await respond(.acceptPrivate) } },
                onAcceptPublicly: { Task { await respond(.accept) } }
            )
        }
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

    private func captureAppreciationViewIfNeeded() {
        guard !didCaptureAppreciationView else { return }
        didCaptureAppreciationView = true
        Analytics.appreciationViewed(
            gratitude,
            viewerId: auth.userId,
            viewerEmail: auth.currentProfile?.email,
            surface: "claim"
        )
    }

    private func trackClaimResponse(_ action: Action) {
        switch action {
        case .accept:
            Analytics.appreciationAccepted(
                gratitudeId: gratitude.id,
                senderId: gratitude.authorId,
                source: analyticsSource,
                visibility: "public"
            )
        case .acceptPrivate:
            Analytics.appreciationAccepted(
                gratitudeId: gratitude.id,
                senderId: gratitude.authorId,
                source: analyticsSource,
                visibility: "private",
                acceptedAsPrivate: true
            )
        case .decline:
            Analytics.appreciationDeclined(
                gratitudeId: gratitude.id,
                senderId: gratitude.authorId,
                source: analyticsSource
            )
        }
    }

    private func respond(_ action: Action) async {
        guard let userId = auth.userId else { return }
        let accepts = action == .accept || action == .acceptPrivate
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
            // Only a public appreciation can be accepted privately. Omit the
            // field otherwise so a plain Accept stays exactly as before.
            let visibility: String? = (action == .acceptPrivate && gratitude.senderMarkedPublic)
                ? "private"
                : nil
            let updated = try await GratitudeService.respondToClaim(
                gratitudeId: gratitude.id,
                recipientId: userId,
                accept: accepts,
                visibility: visibility
            )
            gratitude = updated
            showPrivateConfirm = false
            trackClaimResponse(action)
            if accepts {
                WarmHaptics.received()
                Analytics.capture("pay_it_forward_shown", [
                    "source": "claim_accept",
                    "parent_gratitude_id": updated.id.uuidString.lowercased(),
                ])
                if let onAccepted {
                    onAccepted(updated)
                    acting = nil
                    return
                }
                showPayItForward = true
            }
            withAnimation(Motion.note) {
                outcome = accepts ? .accepted(updated) : .declined
            }
            acting = nil
        } catch is CancellationError {
            acting = nil
        } catch {
            // Already resolved elsewhere — show the accepted/declined outcome.
            if let current = try? await GratitudeService.gratitude(id: gratitude.id) {
                if accepts, current.status == .accepted {
                    gratitude = current
                    showPrivateConfirm = false
                    trackClaimResponse(action)
                    if let onAccepted {
                        onAccepted(current)
                        acting = nil
                        return
                    }
                    withAnimation(Motion.note) { outcome = .accepted(current) }
                    acting = nil
                    return
                }
                if action == .decline, current.status == .rejected {
                    trackClaimResponse(.decline)
                    withAnimation(Motion.note) { outcome = .declined }
                    acting = nil
                    return
                }
            }
            errorMessage = error.localizedDescription
            acting = nil
        }
    }
}

/// Recipient flow for `https://openthanks.com/claim/{token}`.
struct ClaimAppreciationView: View {
    let token: UUID
    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @Environment(\.dismiss) private var dismiss

    @State private var gratitude: Gratitude?
    @State private var phase: Phase = .loading
    /// One `appreciation_viewed` when the claim link resolves to an already
    /// accepted or declined note (the review screen is not shown).
    @State private var didCaptureClaimView = false

    private enum Phase {
        case loading
        case ready
        case missing
        case alreadyProcessed
        case ownAppreciation
        case ownPublished
        case needsSignIn
    }

    var body: some View {
        Group {
            if case .ownAppreciation = phase, let gratitude {
                ComposeView(
                    editing: gratitude,
                    analyticsSource: gratitude.hasNoRecipient ? "watch" : "edit_own",
                    allowsEmptyRecipient: gratitude.hasNoRecipient,
                    opensOnShareScreen: true
                )
            } else {
                claimStack
            }
        }
        .task { await load() }
        .onChange(of: auth.userId) { _, userId in
            if userId != nil, case .needsSignIn = phase {
                Task { await load() }
            }
        }
        .syncAppAppearance()
    }

    private var claimStack: some View {
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
                    messageState(
                        title: "Already processed",
                        body: "This appreciation has already been accepted or declined.",
                        systemImage: "heart"
                    )
                    .onAppear { captureProcessedClaimViewIfNeeded() }
                case .ownAppreciation:
                    EmptyView()
                case .ownPublished:
                    if let gratitude {
                        GratitudeDetailView(gratitude: gratitude)
                    }
                case .ready:
                    if let gratitude {
                        PendingAppreciationReviewView(gratitude: gratitude) { accepted in
                            redirectToAcceptedAppreciation(accepted, offerPayItForward: true)
                        }
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

    private func captureProcessedClaimViewIfNeeded() {
        guard !didCaptureClaimView, let gratitude else { return }
        didCaptureClaimView = true
        Analytics.appreciationViewed(
            gratitude,
            viewerId: auth.userId,
            viewerEmail: auth.currentProfile?.email,
            surface: "claim"
        )
    }

    private func redirectToAcceptedAppreciation(
        _ gratitude: Gratitude,
        offerPayItForward: Bool
    ) {
        let fromName: String?
        if offerPayItForward {
            fromName = gratitude.author?.fullName
                ?? gratitude.author?.displayName
                ?? gratitude.author?.username
                ?? "someone"
        } else {
            fromName = nil
        }
        deepLinks.openAppreciation(gratitude, payItForwardFromName: fromName)
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
                phase = loaded.authorShouldManage(viewerId: auth.userId)
                    ? .ownAppreciation
                    : .ownPublished
                return
            }

            // Already accepted → open the public appreciation page (not the claim UI).
            if loaded.status == .accepted {
                redirectToAcceptedAppreciation(loaded, offerPayItForward: false)
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

/// Quiet text link under the main Accept button. Public stays the default.
struct AcceptPrivatelyLink: View {
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Accept privately")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textTertiary)
                .underline(true, color: Theme.textTertiary.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityHint("Keeps this thank-you between you and the sender")
    }
}

/// Gentle confirmation before a recipient accepts a public appreciation as private.
struct AcceptPrivatelySheet: View {
    let senderName: String?
    var isWorking: Bool
    var errorMessage: String?
    let onKeepPrivate: () -> Void
    let onAcceptPublicly: () -> Void

    private var firstName: String {
        let trimmed = senderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let first = trimmed.split(whereSeparator: \.isWhitespace).first, !first.isEmpty {
            return String(first)
        }
        return "They"
    }

    private var explanation: String {
        "\(firstName) wanted to share this thank-you publicly so others can see it. You can keep it just between the two of you instead. It'll still be yours, it just won't appear in the public feed."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keep this one just between you?")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(explanation)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(13))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onKeepPrivate) {
                Text(isWorking ? "Keeping it private…" : "Keep it private")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(isLoading: isWorking, isEnabled: !isWorking))
            .disabled(isWorking)

            Button(action: onAcceptPublicly) {
                Text("Accept publicly")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .interactiveDismissDisabled(isWorking)
    }
}

/// Small neutral lock. "Accepted privately" when the recipient chose that;
/// "Private" when the sender sent it private.
struct AppreciationPrivacyMark: View {
    var visibility: GratitudeVisibility?
    var acceptedAsPrivate: Bool?
    var fontSize: CGFloat = 12

    private var title: String? {
        if acceptedAsPrivate == true { return "Accepted privately" }
        if visibility == .private { return "Private" }
        return nil
    }

    var body: some View {
        if let title {
            Label(title, systemImage: "lock.fill")
                .font(Theme.body(fontSize, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(title)
        }
    }
}
