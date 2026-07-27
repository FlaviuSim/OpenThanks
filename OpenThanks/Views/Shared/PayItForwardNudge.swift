import SwiftUI

/// Gentle post-accept prompt to pay an appreciation forward.
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
                Image(systemName: "arrow.forward.heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text("Pay it forward")
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

            Text("That felt good — who might love hearing from you next? A short note to someone else keeps the kindness moving.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Inspired by \(firstName)’s appreciation for you.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textTertiary)

            Button(action: onThankSomeone) {
                Text("Thank someone")
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
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
