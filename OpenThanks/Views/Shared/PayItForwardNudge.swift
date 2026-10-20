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
    @State private var didCaptureShown = false
    @State private var showThankBackCompose = false
    @State private var thankBackRecipient: String?

    private var firstName: String {
        guard let fromName, !fromName.isEmpty else { return "someone" }
        return fromName.split(separator: " ").first.map(String.init) ?? fromName
    }

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
                    .accessibilityLabel("Dismiss")
                }
            }

            Text("\(firstName) just thanked you. Send one note to someone who deserves it — keep their kindness moving.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ripple started by \(firstName)")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textTertiary)

            Button(action: onThankSomeone) {
                Text("Thank someone next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle())

            if let fromName, !fromName.isEmpty {
                Button(action: thankSenderBack) {
                    Text(Self.thankBackTitle(for: fromName))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
            }
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
            ComposeView(initialRecipient: thankBackRecipient)
        }
    }

    private func thankSenderBack() {
        if let analyticsParentId {
            Analytics.capture(
                Self.thankBackEventName,
                Self.thankBackProperties(parentGratitudeId: analyticsParentId)
            )
        }
        thankBackRecipient = fromName
        showThankBackCompose = true
    }

    static let thankBackEventName = "thank_back_tapped"

    static func thankBackTitle(for fromName: String) -> String {
        let first = fromName.split(separator: " ").first.map(String.init) ?? fromName
        return "Thank \(first) back"
    }

    static func thankBackProperties(parentGratitudeId: UUID) -> [String: Any] {
        ["parent_gratitude_id": parentGratitudeId.uuidString.lowercased()]
    }

    /// Impression only. PostHog capture enqueues; this does not touch the layout.
    private func captureShownIfNeeded() {
        guard !didCaptureShown,
              let analyticsParentId,
              let analyticsSurface,
              let analyticsSource else { return }
        didCaptureShown = true
        Analytics.payItForwardShown(
            parentGratitudeId: analyticsParentId,
            surface: analyticsSurface,
            source: analyticsSource
        )
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
    @State private var detentHeight: CGFloat = 404

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
                    onThankSomeone()
                    dismiss()
                    AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                },
                onDismiss: {
                    dismiss()
                    AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                },
                analyticsParentId: parentGratitudeId,
                analyticsSurface: analyticsSurface,
                analyticsSource: analyticsSource
            )
            .padding(.horizontal, 20)

            Button("Not now") {
                dismiss()
                AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
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
}

private enum PayItForwardSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
