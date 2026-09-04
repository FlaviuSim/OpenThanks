import SwiftUI

/// Gentle post-accept prompt to continue a gratitude ripple.
struct PayItForwardNudgeCard: View {
    var fromName: String?
    var onThankSomeone: () -> Void
    var onDismiss: (() -> Void)? = nil

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
    }
}

/// Sheet wrapper used right after accepting from the Home feed.
struct PayItForwardSheet: View {
    var fromName: String?
    var onThankSomeone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detentHeight: CGFloat = 340

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Theme.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            PayItForwardNudgeCard(
                fromName: fromName,
                onThankSomeone: {
                    dismiss()
                    AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                    onThankSomeone()
                },
                onDismiss: {
                    dismiss()
                    AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                }
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
            guard height > 0 else { return }
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
