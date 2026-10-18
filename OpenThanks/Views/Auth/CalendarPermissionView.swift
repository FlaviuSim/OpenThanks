import SwiftUI
import UIKit

/// Calendar connect UI — full-screen onboarding gate, or Home-banner sheet.
///
/// App Store 5.1.1(iv): a custom rationale before Calendar access must proceed
/// to the system permission request. Do not offer “Not now” / dismiss that
/// skips EventKit. After the system dialog (allow or deny), leave this screen
/// so the user’s choice is respected.
struct CalendarPermissionView: View {
    var onFinished: () -> Void
    /// Analytics source for connect helpers (`onboarding`, `home_banner`, …).
    var analyticsSource: String = "onboarding"

    @Environment(AuthService.self) private var auth
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @State private var busyApple = false
    @State private var busyGoogle = false
    @State private var errorMessage: String?
    @State private var appeared = false
    /// After EventKit was prompted (or was already decided), offer Settings + Done.
    @State private var showPostDenialActions = false

    private var busy: Bool { busyApple || busyGoogle }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                ActionGlyph(systemImage: "calendar", size: 80)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                VStack(spacing: 10) {
                    Text("Turn busy days into gratitude")
                        .font(Theme.display(28, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Connect a calendar and we’ll suggest one person to thank from today’s meetings — a weekday evening nudge at 8 so good days end feeling fuller.")
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .softNoteReveal(delay: 0.04)

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }

                Text("Choose one to continue")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .softNoteReveal(delay: 0.1)

                CalendarSourceChoice(
                    title: "Apple Calendar",
                    subtitle: "Meetings stay on this device — you’ll get a permission prompt next",
                    systemImage: "apple.logo",
                    isBusy: busyApple,
                    disabled: busy
                ) {
                    Task { await connectApple() }
                }
                .softNoteReveal(delay: 0.16)

                CalendarSourceChoice(
                    title: "Google Calendar",
                    subtitle: "Reads today’s meetings only — we don’t store them",
                    systemImage: "g.circle.fill",
                    isBusy: busyGoogle,
                    disabled: busy
                ) {
                    Task { await connectGoogle() }
                }
                .softNoteReveal(delay: 0.22)

                Text("You can connect the other one anytime in Settings.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .softNoteReveal(delay: 0.28)

                // Only after the system Calendar prompt was shown (or access was
                // already decided). Never a way to skip the permission request.
                if showPostDenialActions {
                    Button {
                        openSystemSettings()
                    } label: {
                        Text("Open Settings")
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .disabled(busy)

                    Button {
                        finishWithoutCalendar()
                    } label: {
                        Text("Continue without calendar")
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .disabled(busy)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .syncAppAppearance()
        .readableWidth()
        .animation(.easeOut(duration: 0.2), value: errorMessage)
        .animation(.easeOut(duration: 0.2), value: showPostDenialActions)
        .onAppear {
            Analytics.calendarPermissionPrompted(source: analyticsSource)
            withAnimation(.easeOut(duration: 0.45)) {
                appeared = true
            }
        }
    }

    private func connectApple() async {
        busyApple = true
        errorMessage = nil
        defer { busyApple = false }

        let wasUndetermined = CalendarMeetingService.accessState == .notDetermined
        let granted = await CalendarMeetingService.requestAccess(analyticsSource: analyticsSource)

        if granted {
            showPostDenialActions = false
            await finishWithNudge(requestAppleIfNeeded: false)
            return
        }

        // System dialog was shown (or access was already denied). Respect the
        // choice — never leave a “Not now” path that avoids EventKit.
        if wasUndetermined {
            // Just denied the first prompt: continue into the app.
            finishWithoutCalendar()
            return
        }

        // Previously denied / restricted — point to Settings, then allow Done.
        errorMessage = "Calendar access is off. Enable it in Settings to get meeting thank-you ideas."
        showPostDenialActions = true
    }

    private func connectGoogle() async {
        busyGoogle = true
        errorMessage = nil
        defer { busyGoogle = false }

        do {
            try await GoogleCalendarAuth.connect(analyticsSource: analyticsSource)
            showPostDenialActions = false
            await finishWithNudge(requestAppleIfNeeded: false)
        } catch {
            if GoogleCalendarAuth.isUserCancellation(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func finishWithNudge(requestAppleIfNeeded: Bool) async {
        let failure = await NotificationService.enableCalendarGratitudeNudge(
            authorId: auth.userId,
            selfEmails: selfEmails,
            requestAppleIfNeeded: requestAppleIfNeeded,
            analyticsSource: analyticsSource
        )
        calendarNudgeEnabled = failure == nil
        if failure == nil {
            CalendarGratitudeBackgroundRefresh.schedule()
            onFinished()
        } else if failure == .notificationsDenied {
            errorMessage = "Notifications are needed for evening thank-you nudges. Enable them in iPhone Settings."
            showPostDenialActions = true
        } else {
            errorMessage = "Pick Apple or Google Calendar to turn on evening thank-you nudges."
        }
    }

    private var selfEmails: Set<String> {
        var emails = Set<String>()
        if let email = auth.currentProfile?.email?.lowercased() {
            emails.insert(email)
        }
        return emails
    }

    private func finishWithoutCalendar() {
        Analytics.calendarPermissionSkipped(source: analyticsSource)
        calendarNudgeEnabled = false
        Task { await NotificationService.disableCalendarGratitudeNudge() }
        onFinished()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Interactive choice row for Apple or Google Calendar.
private struct CalendarSourceChoice: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isBusy: Bool
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.coral.opacity(0.18))
                        .frame(width: 48, height: 48)
                    if isBusy {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(Theme.coral)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                            .symbolRenderingMode(.monochrome)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.body(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(isBusy ? "Connecting…" : subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .opacity(isBusy ? 0 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CalendarChoicePressStyle())
        .disabled(disabled)
        .opacity(disabled && !isBusy ? 0.55 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct CalendarChoicePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
