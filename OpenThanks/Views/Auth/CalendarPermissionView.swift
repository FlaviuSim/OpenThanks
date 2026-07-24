import SwiftUI

/// Shown once after notification permission — evening thank-you nudges default on.
struct CalendarPermissionView: View {
    var onFinished: () -> Void

    @Environment(AuthService.self) private var auth
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ActionGlyph(systemImage: "calendar", size: 88)

                VStack(spacing: 10) {
                    Text("Thank people from your day")
                        .font(Theme.display(28, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Allow Calendar so OpenThanks can suggest one person from today’s meetings each weekday evening. Events stay on your device.")
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await allowCalendar() }
                } label: {
                    HStack(spacing: 10) {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: 0x2B1209))
                        }
                        Text(busy ? "Enabling…" : "Allow Calendar")
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
    }

    private func allowCalendar() async {
        busy = true
        defer { busy = false }

        var emails = Set<String>()
        if let email = auth.currentProfile?.email?.lowercased() {
            emails.insert(email)
        }

        let enabled = await NotificationService.enableCalendarGratitudeNudge(
            authorId: auth.userId,
            selfEmails: emails
        )
        calendarNudgeEnabled = enabled
        if enabled {
            CalendarGratitudeBackgroundRefresh.schedule()
        }
        onFinished()
    }

    private func skip() {
        calendarNudgeEnabled = false
        Task { await NotificationService.disableCalendarGratitudeNudge() }
        onFinished()
    }
}
