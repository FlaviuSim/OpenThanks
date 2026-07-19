import SwiftUI

/// Actions for nudging a recipient after creating or from Pending Appreciations.
/// Shows Copy Link / Text / Email / OpenThanks Email Reminder — not the raw URL string.
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

                ShareActionRow(
                    title: "Send via Text",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    subtitle: gratitude.recipientPhone.map { "To \($0)" }
                ) {
                    openSMS()
                }

                ShareActionRow(
                    title: "Send via Email",
                    systemImage: "envelope.fill",
                    subtitle: recipientEmail.map { "To \($0)" }
                ) {
                    openMail()
                }

                if let recipientEmail {
                    ShareActionRow(
                        title: emailActionTitle,
                        systemImage: emailActionIcon,
                        subtitle: emailSubtitle(for: recipientEmail),
                        showSpinner: emailState == .sending,
                        disabled: emailState == .sending
                    ) {
                        Task { await sendEmailReminder() }
                    }
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
        case .idle, .sending: "envelope.fill"
        case .sent: "checkmark"
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

    private func openMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipientEmail ?? ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: "I wrote you an appreciation on OpenThanks"),
            URLQueryItem(name: "body", value: messageBody),
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}
