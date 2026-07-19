import SwiftUI

/// Shown once after sign-in (and profile completion) before the main app.
/// Friday reminder defaults on; we ask for notification permission here.
struct NotificationPermissionView: View {
    var onFinished: () -> Void

    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ActionGlyph(systemImage: "bell.fill", size: 88)

                VStack(spacing: 10) {
                    Text("Stay in the gratitude loop")
                        .font(Theme.display(28, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Get a gentle Friday morning reminder to appreciate someone who made your week better.")
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
                    Task { await allowNotifications() }
                } label: {
                    HStack(spacing: 10) {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: 0x2B1209))
                        }
                        Text(busy ? "Enabling…" : "Allow Notifications")
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

    private func allowNotifications() async {
        busy = true
        defer { busy = false }
        let enabled = await NotificationService.enableFridayReminder()
        fridayReminderEnabled = enabled
        onFinished()
    }

    private func skip() {
        fridayReminderEnabled = false
        Task { await NotificationService.disableFridayReminder() }
        onFinished()
    }
}
