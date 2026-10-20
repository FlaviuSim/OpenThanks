import SwiftUI

/// Gentle post-accept prompt to continue a gratitude ripple.
struct PayItForwardNudgeCard: View {
    var fromName: String?
    var onThankSomeone: () -> Void
    var onDismiss: (() -> Void)? = nil
    /// When all three are set, `pay_it_forward_shown` fires once from `onAppear`.
    var analyticsParentId: UUID? = nil
    var analyticsSurface: String? = nil
    var analyticsSource: String? = nil
    /// Sheet host presents compose from the tab after the detent closes.
    /// Inline cards leave this nil and present compose themselves.
    var onThankBack: ((PayItForwardThankBackLaunch) -> Void)? = nil
    @State private var didCaptureShown = false
    @State private var showThankBackCompose = false
    @State private var thankBackRecipient: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "water.waves")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text("Continue the ripple")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(PayItForwardNudgeBehavior.dismissAccessibilityLabel)
                }
            }

            Text(PayItForwardNudgeBehavior.promptBody(from: fromName))
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(PayItForwardNudgeBehavior.rippleCaption(from: fromName))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textTertiary)

            Button(action: onThankSomeone) {
                Text(PayItForwardNudgeBehavior.primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle())

            Button(action: thankSenderBack) {
                Text(PayItForwardNudgeBehavior.thankBackButtonTitle(from: fromName))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.coral.opacity(0.35), lineWidth: 1)
                )
        )
        .onAppear(perform: captureShownIfNeeded)
        .composeCover(isPresented: $showThankBackCompose) {
            ComposeView(
                initialRecipient: thankBackRecipient,
                analyticsSource: PayItForwardNudgeBehavior.thankBackComposeSource
            )
        }
    }

    /// Impression only. PostHog capture enqueues; this does not touch the layout.
    private func captureShownIfNeeded() {
        guard let shown = PayItForwardNudgeBehavior.shownCapture(
            alreadyCaptured: didCaptureShown,
            parentId: analyticsParentId,
            surface: analyticsSurface,
            source: analyticsSource
        ) else { return }
        didCaptureShown = true
        Analytics.payItForwardShown(
            parentGratitudeId: shown.parentId,
            surface: shown.surface,
            source: shown.source
        )
    }

    private func thankSenderBack() {
        let capture = PayItForwardNudgeBehavior.thankBackCapture(
            parentGratitudeId: analyticsParentId
        )
        Analytics.capture(capture.event, capture.properties)
        let launch = PayItForwardNudgeBehavior.thankBackLaunch(fromName: fromName)
        if let onThankBack {
            onThankBack(launch)
        } else {
            thankBackRecipient = launch.recipientName
            showThankBackCompose = true
            AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
        }
    }
}

/// Sheet wrapper used right after accepting from the Home feed.
struct PayItForwardSheet: View {
    var fromName: String?
    var parentGratitudeId: UUID?
    var analyticsSurface: String
    var analyticsSource: String
    var onThankSomeone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(DeepLinkRouter.self) private var deepLinks
    @State private var detentHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Theme.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            PayItForwardNudgeCard(
                fromName: fromName,
                onThankSomeone: {
                    // Tell the host this was a tap before `dismiss()` flips the
                    // presentation binding, so that path is not counted as a dismiss.
                    perform(.thankSomeoneElse)
                },
                onDismiss: { perform(.dismiss) },
                analyticsParentId: parentGratitudeId,
                analyticsSurface: analyticsSurface,
                analyticsSource: analyticsSource,
                onThankBack: { launch in
                    presentThankBack(launch)
                }
            )
            .padding(.horizontal, 20)

            Button(PayItForwardNudgeBehavior.notNowTitle) {
                perform(.dismiss)
            }
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Ideal height only — measuring the detent container itself cycles AttributeGraph
        // (detent → GeometryReader → detentHeight → detent…).
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.background)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PayItForwardSheetHeightKey.self,
                    value: geo.size.height
                )
            }
        }
        .onPreferenceChange(PayItForwardSheetHeightKey.self) { height in
            guard height.isFinite, height > 0, abs(height - detentHeight) > 1 else { return }
            detentHeight = height
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.hidden)
    }

    /// Same side effects as before: thank-someone notifies the host, then the
    /// sheet closes and the review prompt is scheduled. Dismiss only closes.
    private func perform(_ tap: PayItForwardSheetTap) {
        let plan = PayItForwardNudgeBehavior.sheetTapPlan(tap)
        if plan.forwardsThankSomeone {
            onThankSomeone()
        }
        if plan.dismissesSheet {
            dismiss()
        }
        if plan.schedulesReviewPrompt {
            AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
        }
    }

    /// Detent sheets trap a compose cover. Queue the shared compose presenter,
    /// which clears the feed sheet, and drop a claim cover that would sit on top.
    private func presentThankBack(_ launch: PayItForwardThankBackLaunch) {
        ComposeLaunchBridge.shared.queue(
            recipientName: launch.recipientName,
            analyticsSource: launch.analyticsSource
        )
        if deepLinks.destination != nil || deepLinks.payItForwardFromName != nil {
            // Clear the nudge before the cover. `clear()` drops the destination
            // first, and that dismissal would otherwise look like Not now.
            deepLinks.payItForwardFromName = nil
            deepLinks.payItForwardParentId = nil
            deepLinks.destination = nil
        }
        AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
    }
}

enum PayItForwardSheetTap: Equatable {
    case thankSomeoneElse
    case dismiss
}

struct PayItForwardSheetTapPlan: Equatable {
    var forwardsThankSomeone: Bool
    var dismissesSheet: Bool
    var schedulesReviewPrompt: Bool
}

struct PayItForwardShownCapture: Equatable {
    var parentId: UUID
    var surface: String
    var source: String
}

struct PayItForwardThankBackLaunch: Equatable {
    var recipientName: String?
    var analyticsSource: String
}

struct PayItForwardThankBackCapture: Equatable {
    var event: String
    var parentGratitudeId: String?

    var properties: [String: Any] {
        guard let parentGratitudeId else { return [:] }
        return ["parent_gratitude_id": parentGratitudeId]
    }
}

enum PayItForwardNudgeBehavior {
    static let primaryButtonTitle = "Thank someone next"
    static let notNowTitle = "Not now"
    static let dismissAccessibilityLabel = "Dismiss"
    static let thankBackEventName = "thank_back_tapped"
    static let thankBackComposeSource = "post_accept_thank_back"

    static func senderFirstName(from fromName: String?) -> String {
        guard let fromName, !fromName.isEmpty else { return "someone" }
        return fromName.split(separator: " ").first.map(String.init) ?? fromName
    }

    static func promptBody(from fromName: String?) -> String {
        let firstName = senderFirstName(from: fromName)
        return "\(firstName) just thanked you. Send one note to someone who deserves it — keep their kindness moving."
    }

    static func rippleCaption(from fromName: String?) -> String {
        "Ripple started by \(senderFirstName(from: fromName))"
    }

    static func thankBackButtonTitle(from fromName: String?) -> String {
        "Thank \(senderFirstName(from: fromName)) back"
    }

    /// Trimmed sender name for the compose recipient field. Blank names stay unset.
    static func thankBackRecipientName(from fromName: String?) -> String? {
        guard let fromName else { return nil }
        let trimmed = fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func thankBackLaunch(fromName: String?) -> PayItForwardThankBackLaunch {
        PayItForwardThankBackLaunch(
            recipientName: thankBackRecipientName(from: fromName),
            analyticsSource: thankBackComposeSource
        )
    }

    static func thankBackCapture(parentGratitudeId: UUID?) -> PayItForwardThankBackCapture {
        PayItForwardThankBackCapture(
            event: thankBackEventName,
            parentGratitudeId: parentGratitudeId?.uuidString.lowercased()
        )
    }

    static func shownCapture(
        alreadyCaptured: Bool,
        parentId: UUID?,
        surface: String?,
        source: String?
    ) -> PayItForwardShownCapture? {
        guard !alreadyCaptured,
              let parentId,
              let surface,
              let source else { return nil }
        return PayItForwardShownCapture(
            parentId: parentId,
            surface: surface,
            source: source
        )
    }

    static func sheetTapPlan(_ tap: PayItForwardSheetTap) -> PayItForwardSheetTapPlan {
        switch tap {
        case .thankSomeoneElse:
            return PayItForwardSheetTapPlan(
                forwardsThankSomeone: true,
                dismissesSheet: true,
                schedulesReviewPrompt: true
            )
        case .dismiss:
            return PayItForwardSheetTapPlan(
                forwardsThankSomeone: false,
                dismissesSheet: true,
                schedulesReviewPrompt: true
            )
        }
    }
}

private enum PayItForwardSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
