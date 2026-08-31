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

    /// Prefer @username / name on the row; mailto still uses the real address when known.
    private var emailToLabel: String {
        if let username = gratitude.recipient?.username.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return "To @\(username)"
        }
        if let name = gratitude.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "To \(name)"
        }
        if let display = gratitude.recipient?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !display.isEmpty {
            return "To \(display)"
        }
        if recipientEmail != nil {
            return "To their email"
        }
        return "Choose an address"
    }

    private var messageBody: String {
        let greeting = gratitude.shareGreetingFirstName.map { "Hey \($0)! " } ?? "Hey! "
        let preview = Self.messagePreview(gratitude.message)
        let previewBit = preview.map { " It starts: “\($0)”" } ?? ""
        return greeting
            + "I wrote you an appreciation on OpenThanks 💛\(previewBit) You can read and accept it here: "
            + shareURL.absoluteString
    }

    private static func messagePreview(_ message: String, maxChars: Int = 120) -> String? {
        let trimmed = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxChars { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        var slice = String(trimmed[..<end])
        if let lastSpace = slice.lastIndex(of: " "),
           slice.distance(from: slice.startIndex, to: lastSpace) > 40 {
            slice = String(slice[..<lastSpace])
        }
        return slice.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Theme.hairline)
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                VStack(spacing: 10) {
                    Text("Nudge \(gratitude.recipientDisplayName)")
                        .font(Theme.display(22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("They haven't accepted yet. Send the link so they can see it and accept.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)

                if gratitude.emailDeliveryFailed {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                            .font(.system(size: 16, weight: .semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                gratitude.recipientEmailStatus == "bounced"
                                    ? "Email bounced — address may be invalid"
                                    : "Notification email wasn't delivered"
                            )
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            Text(
                                "We couldn't deliver to \(gratitude.recipientEmail ?? "that address"). Share the claim link another way, or edit the email and try again."
                            )
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.coral.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 20) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Send them the link")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .padding(.leading, 4)

                        VStack(spacing: 10) {
                            ShareActionRow(
                                title: "Text Message",
                                systemImage: "bubble.left.and.bubble.right.fill",
                                subtitle: gratitude.recipientPhone.map { "To \($0)" }
                                    ?? "Opens Messages with the link"
                            ) {
                                openSMS()
                            }

                            ShareActionRow(
                                title: "WhatsApp",
                                systemImage: "phone.bubble.fill",
                                subtitle: gratitude.recipientPhone.map { "To \($0)" }
                                    ?? "Opens Whatsapp with the link"
                            ) {
                                openWhatsApp()
                            }

                            ShareActionRow(
                                title: "Email",
                                systemImage: "envelope.fill",
                                subtitle: emailToLabel
                            ) {
                                openMail()
                            }

                            if recipientEmail != nil || gratitude.recipientId != nil {
                                ShareActionRow(
                                    title: emailActionTitle,
                                    systemImage: emailActionIcon,
                                    subtitle: emailSubtitle(),
                                    showSpinner: emailState == .sending,
                                    disabled: emailState == .sending
                                ) {
                                    Task { await sendEmailReminder() }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                Button("Done") { dismiss() }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.bottom, 8)
            }
            .readableWidth(420)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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
        case .sent: "checkmark"
        case .failed: "arrow.clockwise"
        }
    }

    private func emailSubtitle() -> String {
        let destination: String = {
            if let username = gratitude.recipient?.username.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                return "@\(username)"
            }
            if let name = gratitude.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
            return "them"
        }()
        switch emailState {
        case .idle, .sending: return "OpenThanks emails \(destination)"
        case .sent: return "Reminder delivered"
        case .failed(let message): return message
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
        var components = URLComponents()
        components.scheme = "sms"
        if let phone = gratitude.recipientPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty {
            components.path = phone
        }
        components.queryItems = [URLQueryItem(name: "body", value: messageBody)]
        if let url = components.url {
            openURL(url)
        }
    }

    private func openMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        if let email = gratitude.shareMailtoEmail {
            components.path = email
        }
        components.queryItems = [
            URLQueryItem(name: "subject", value: "I wrote you an appreciation on OpenThanks"),
            URLQueryItem(name: "body", value: messageBody),
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private func openWhatsApp() {
        if let url = ShareChannels.whatsAppURL(
            message: messageBody,
            phone: gratitude.recipientPhone
        ) {
            openURL(url)
        }
    }
}
