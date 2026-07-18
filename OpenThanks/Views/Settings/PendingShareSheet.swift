import SwiftUI

/// Actions for nudging a recipient after creating or from Pending Appreciations.
/// Shows Copy Link / Text / OpenThanks Email Reminder — not the raw URL string.
struct PendingShareSheet: View {
    let gratitude: Gratitude
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var emailState: EmailState = .idle

    private enum EmailState: Equatable {
        case idle, sending, sent, failed(String)
    }

    private var shareURL: URL {
        gratitude.claimURL ?? AppConfig.webAppURL
    }

    private var recipientEmail: String? {
        let value = gratitude.recipientEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var messageBody: String {
        let name = gratitude.recipientName?.split(separator: " ").first.map(String.init)
            ?? gratitude.recipient?.fullName?.split(separator: " ").first.map(String.init)
        let greeting = name.map { "Hey \($0)! " } ?? "Hey! "
        return greeting
            + "I wrote you an appreciation on OpenThanks 💛 You can read and claim it here: "
            + shareURL.absoluteString
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(Theme.hairline).frame(width: 36, height: 4)
                .padding(.top, 10)

            VStack(spacing: 6) {
                Text("Nudge \(gratitude.recipientDisplayName)")
                    .font(Theme.display(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("They haven't claimed your appreciation yet. Send them the link directly.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = shareURL.absoluteString
                    withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "link")
                            .font(.system(size: 15, weight: .bold))
                        Text(copied ? "Link Copied!" : "Copy Link")
                    }
                }
                .buttonStyle(CTAButtonStyle())
                .sensoryFeedback(.success, trigger: copied)

                if let recipientEmail {
                    shareAction(
                        title: emailActionTitle,
                        systemImage: emailActionIcon,
                        subtitle: emailSubtitle(for: recipientEmail),
                        showSpinner: emailState == .sending,
                        disabled: emailState == .sending
                    ) {
                        Task { await sendEmailReminder() }
                    }
                }

                shareAction(
                    title: "Send via Text",
                    systemImage: "message.fill",
                    subtitle: gratitude.recipientPhone.map { "To \($0)" }
                ) {
                    openSMS()
                }
            }
            .padding(.horizontal, 24)

            Button("Done") { dismiss() }
                .font(Theme.body(16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    private var emailActionTitle: String {
        switch emailState {
        case .idle: "Email Reminder"
        case .sending: "Sending…"
        case .sent: "Email Sent!"
        case .failed: "Retry Email Reminder"
        }
    }

    private var emailActionIcon: String {
        switch emailState {
        case .idle, .sending: "envelope.badge.fill"
        case .sent: "checkmark.circle.fill"
        case .failed: "arrow.clockwise"
        }
    }

    private func emailSubtitle(for email: String) -> String {
        switch emailState {
        case .idle, .sending: "OpenThanks emails \(email)"
        case .sent: "Reminder delivered to \(email)"
        case .failed(let message): message
        }
    }

    private func shareAction(
        title: String,
        systemImage: String,
        subtitle: String?,
        showSpinner: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.coralPale.opacity(0.55))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if showSpinner {
                    ProgressView().tint(Theme.coral)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
            .opacity(disabled ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func sendEmailReminder() async {
        emailState = .sending
        do {
            try await GratitudeService.sendEmailReminder(gratitudeId: gratitude.id)
            emailState = .sent
            try? await Task.sleep(for: .seconds(2.5))
            if case .sent = emailState { emailState = .idle }
        } catch {
            emailState = .failed(error.localizedDescription)
        }
    }

    private func openSMS() {
        let phone = gratitude.recipientPhone ?? ""
        var components = URLComponents()
        components.scheme = "sms"
        components.path = phone
        components.queryItems = [URLQueryItem(name: "body", value: messageBody)]
        if let url = components.url {
            openURL(url)
        }
    }
}
