import SwiftUI

/// Two-step love prompt after a successful send: review on the App Store, or private feedback.
struct EnjoyingOpenThanksSheet: View {
    var preferredEmail: String?
    var preferredName: String?
    var onFinished: () -> Void

    private enum Step {
        case ask
        case love
        case feedback
        case feedbackThanks
    }

    @Environment(\.openURL) private var openURL
    @State private var step: Step = .ask
    @State private var feedback = ""
    @State private var email = ""
    @State private var sending = false
    @State private var errorMessage: String?
    /// Prevents double-counting when buttons call `onFinished` (which dismisses the sheet).
    @State private var didSettle = false
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            Group {
                switch step {
                case .ask: askStep
                case .love: loveStep
                case .feedback: feedbackStep
                case .feedbackThanks: thanksStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .animation(Motion.breathe, value: step)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .presentationDetents([.height(step == .feedback ? 440 : 340)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            if email.isEmpty {
                email = preferredEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            Analytics.capture("enjoyment_prompt_shown")
        }
        .interactiveDismissDisabled(sending)
        .onDisappear {
            if EnjoymentPrompt.ignoreNextSheetDismiss {
                EnjoymentPrompt.ignoreNextSheetDismiss = false
                return
            }
            // Swipe-away without finishing counts as a soft dismiss (cooldown).
            guard !didSettle, !EnjoymentPrompt.hasCompleted else { return }
            switch step {
            case .ask, .love, .feedback:
                EnjoymentPrompt.markDismissed()
                Analytics.capture("enjoyment_prompt_dismissed", ["via": "swipe", "step": "\(step)"])
            case .feedbackThanks:
                break
            }
        }
    }

    private func settle(dismissCooldown: Bool, event: String? = nil, props: [String: Any] = [:]) {
        didSettle = true
        if dismissCooldown {
            EnjoymentPrompt.markDismissed()
        }
        if let event {
            Analytics.capture(event, props)
        }
        onFinished()
    }

    private var askStep: some View {
        VStack(spacing: 18) {
            ActionGlyph(systemImage: "heart.fill", size: 64)
                .softNoteReveal(delay: 0.02)

            VStack(spacing: 8) {
                Text("Enjoying OpenThanks?")
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("You’re helping kindness travel — that means a lot.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .softNoteReveal(delay: 0.06)

            VStack(spacing: 10) {
                Button {
                    Analytics.capture("enjoyment_prompt_yes")
                    withAnimation(Motion.breathe) { step = .love }
                } label: {
                    Text("Yes, love it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle())

                Button {
                    Analytics.capture("enjoyment_prompt_no")
                    withAnimation(Motion.breathe) { step = .feedback }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        feedbackFocused = true
                    }
                } label: {
                    Text("Not really")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())

                Button {
                    settle(
                        dismissCooldown: true,
                        event: "enjoyment_prompt_dismissed",
                        props: ["via": "not_now"]
                    )
                } label: {
                    Text("Not now")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .softNoteReveal(delay: 0.1)
        }
    }

    private var loveStep: some View {
        VStack(spacing: 18) {
            ActionGlyph(systemImage: "star.fill", size: 64)

            VStack(spacing: 8) {
                Text("Thank you")
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("A short review helps others find OpenThanks — it only takes a moment.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    didSettle = true
                    EnjoymentPrompt.markCompleted()
                    Analytics.capture("enjoyment_prompt_review_opened")
                    openURL(EnjoymentPrompt.writeReviewURL)
                    onFinished()
                } label: {
                    Text("Leave a review")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle())

                Button {
                    settle(
                        dismissCooldown: true,
                        event: "enjoyment_prompt_dismissed",
                        props: ["via": "maybe_later"]
                    )
                } label: {
                    Text("Maybe later")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var feedbackStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("We’re sorry it’s not clicking")
                    .font(Theme.display(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Want to tell us what’s off? Private note — not a public review.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Your email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

            TextField("What’s not working for you?", text: $feedback, axis: .vertical)
                .lineLimit(4...8)
                .focused($feedbackFocused)
                .padding(12)
                .frame(minHeight: 110, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(13))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await sendFeedback() }
            } label: {
                Text(sending ? "Sending…" : "Send feedback")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(isLoading: sending))
            .disabled(sending)

            Button {
                settle(
                    dismissCooldown: true,
                    event: "enjoyment_prompt_dismissed",
                    props: ["via": "feedback_skip"]
                )
            } label: {
                Text("Skip")
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(sending)

            Button {
                openMailtoFallback()
            } label: {
                Text("Or email founders@openthanks.com")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(sending)
        }
    }

    private var thanksStep: some View {
        VStack(spacing: 18) {
            ActionGlyph(systemImage: "checkmark.circle.fill", size: 64)

            VStack(spacing: 8) {
                Text("Thanks — we read every note")
                    .font(Theme.display(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Your feedback helps us make OpenThanks kinder.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                didSettle = true
                onFinished()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle())
        }
    }

    private func sendFeedback() async {
        sending = true
        errorMessage = nil
        defer { sending = false }
        do {
            try await SupportFeedbackService.send(
                name: preferredName,
                email: email,
                message: feedback
            )
            didSettle = true
            EnjoymentPrompt.markCompleted()
            Analytics.capture("enjoyment_prompt_feedback_sent")
            withAnimation(Motion.breathe) { step = .feedbackThanks }
        } catch {
            errorMessage = error.localizedDescription
            Analytics.capture("enjoyment_prompt_feedback_failed", [
                "error": error.localizedDescription,
            ])
        }
    }

    private func openMailtoFallback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "founders@openthanks.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "OpenThanks in-app feedback"),
            URLQueryItem(name: "body", value: feedback.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}
