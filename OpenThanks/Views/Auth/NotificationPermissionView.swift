import SwiftUI
import UIKit

/// Deferred notification permission UI — after send/accept, or right after calendar connect.
struct NotificationPermissionView: View {
    enum Pitch: Equatable {
        /// Don’t miss receives + recipient accept confirms.
        case appreciation
        /// Evening calendar nudges need alerts.
        case postCalendar
    }

    var onFinished: () -> Void
    var pitch: Pitch = .appreciation
    /// Analytics source (`post_send`, `post_accept`, `post_calendar`, …).
    var analyticsSource: String = "post_send"

    @Environment(AuthService.self) private var auth
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @State private var busy = false
    @State private var systemDenied = false

    private var headline: String {
        switch pitch {
        case .appreciation:
            return "Don’t miss kindness coming back"
        case .postCalendar:
            return "Turn on notifications for evening thank-you ideas"
        }
    }

    private var bodyCopy: String {
        switch pitch {
        case .appreciation:
            return "We’ll let you know when someone appreciates you, and when they accept the note you sent — so nothing important slips by."
        case .postCalendar:
            return "Your calendar is connected. Notifications are needed to deliver the weekday 8pm nudge with someone to thank from today’s meetings."
        }
    }

    private var primaryTitle: String {
        if systemDenied { return "Open Settings" }
        return busy ? "Enabling…" : "Allow Notifications"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ActionGlyph(systemImage: "bell.fill", size: 88)

                VStack(spacing: 10) {
                    Text(headline)
                        .font(Theme.display(28, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(bodyCopy)
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    if systemDenied {
                        Text("Notifications are off for OpenThanks. Turn them on in iPhone Settings to continue.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await primaryAction() }
                } label: {
                    HStack(spacing: 10) {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: 0x2B1209))
                        }
                        Text(primaryTitle)
                    }
                }
                .buttonStyle(CTAButtonStyle(isLoading: busy))
                .disabled(busy)

                Button {
                    skip()
                } label: {
                    Text("Not now")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .disabled(busy)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .syncAppAppearance()
        .readableWidth()
        .task {
            systemDenied = await NotificationService.authorizationStatus() == .denied
            Analytics.pushPermissionPrompted(source: analyticsSource, prePrompt: true)
        }
    }

    private func primaryAction() async {
        if systemDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
            return
        }

        busy = true
        defer { busy = false }

        switch pitch {
        case .appreciation:
            let failure = await NotificationService.enableFridayReminder(analyticsSource: analyticsSource)
            fridayReminderEnabled = failure == nil
            if failure == .notificationsDenied {
                systemDenied = true
                return
            }
        case .postCalendar:
            let granted = await NotificationService.requestAuthorizationAndRegisterForPushes(
                analyticsSource: analyticsSource
            )
            guard granted else {
                systemDenied = await NotificationService.authorizationStatus() == .denied
                return
            }
            fridayReminderEnabled = true
            _ = await NotificationService.enableFridayReminder(analyticsSource: analyticsSource)
            var emails = Set<String>()
            if let email = auth.currentProfile?.email?.lowercased() {
                emails.insert(email)
            }
            let failure = await NotificationService.enableCalendarGratitudeNudge(
                authorId: auth.userId,
                selfEmails: emails,
                requestAppleIfNeeded: false,
                analyticsSource: analyticsSource
            )
            calendarNudgeEnabled = failure == nil
            if failure == nil {
                CalendarGratitudeBackgroundRefresh.schedule()
            }
        }

        PermissionPromptScheduler.shared.markNotificationPromptCompleted()
        onFinished()
    }

    private func skip() {
        switch pitch {
        case .appreciation:
            fridayReminderEnabled = false
            Task { await NotificationService.disableFridayReminder() }
        case .postCalendar:
            // Calendar stays connected; evening nudge waits until notifications are on.
            calendarNudgeEnabled = false
            Task { await NotificationService.disableCalendarGratitudeNudge() }
        }
        PermissionPromptScheduler.shared.markNotificationPromptCompleted()
        onFinished()
    }
}
