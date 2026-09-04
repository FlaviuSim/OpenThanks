import SwiftUI
import UIKit

/// Friday reminder + evening calendar nudge, with clear on/off effects and calendar sources.
struct NotificationsSettingsView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @State private var calendarAccessTick = 0
    @State private var googleBusy = false
    @State private var errorMessage: String?
    @State private var showOpenSystemSettings = false
    @State private var fridayToggleTask: Task<Void, Never>?
    @State private var calendarToggleTask: Task<Void, Never>?
    @State private var fridayToggleEpoch = 0
    @State private var calendarToggleEpoch = 0
    @State private var previewBusy = false
    @State private var previewStatus: String?

    private var fridayBinding: Binding<Bool> {
        Binding(
            get: { fridayReminderEnabled },
            set: { setFridayReminderEnabled($0) }
        )
    }

    private var calendarBinding: Binding<Bool> {
        Binding(
            get: { calendarNudgeEnabled },
            set: { setCalendarNudgeEnabled($0) }
        )
    }

    private var appleReady: Bool {
        _ = calendarAccessTick
        return CalendarMeetingService.hasFullAccess
    }

    private var googleReady: Bool {
        _ = calendarAccessTick
        return GoogleCalendarService.isConnected
    }

    private var anyCalendarReady: Bool {
        appleReady || googleReady
    }

    private var appleStatus: String {
        _ = calendarAccessTick
        switch CalendarMeetingService.accessState {
        case .fullAccess: return "On"
        case .writeOnly: return "Needs full access"
        case .denied, .restricted: return "Off"
        case .notDetermined: return "Not connected"
        }
    }

    private var googleStatus: String {
        googleReady ? "On" : "Off"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro

                reminderCard(
                    title: "Friday gratitude reminder",
                    whenOn: "You’ll get a gentle prompt every Friday at 9:00 AM.",
                    whenOff: "No Friday reminder.",
                    isOn: fridayReminderEnabled,
                    binding: fridayBinding
                )

                VStack(alignment: .leading, spacing: 14) {
                    reminderCard(
                        title: "Evening thank-you nudge",
                        whenOn: "On weekdays at 8:00 PM, we’ll suggest one person from today’s meetings — only if a calendar is connected.",
                        whenOff: "No evening calendar suggestion.",
                        isOn: calendarNudgeEnabled,
                        binding: calendarBinding
                    )

                    if calendarNudgeEnabled {
                        calendarSources
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: calendarNudgeEnabled)

                if let errorMessage {
                    errorBlock(errorMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .tabChromeBottomPadding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .syncAppAppearance()
        .onAppear { calendarAccessTick += 1 }
        .onDisappear {
            fridayToggleTask?.cancel()
            calendarToggleTask?.cancel()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose which reminders you want. Each one can be turned off anytime.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reminderCard(
        title: String,
        whenOn: String,
        whenOff: String,
        isOn: Bool,
        binding: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: binding) {
                Text(title)
                    .font(Theme.body(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.coral)

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(isOn ? Theme.coral : Theme.textTertiary.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                Text(isOn ? whenOn : whenOff)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var calendarSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendars for suggestions")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    anyCalendarReady
                        ? "We’ll use connected calendars to pick someone from your day. Events aren’t stored on OpenThanks servers."
                        : "Connect Apple or Google so we know who you met today. Without a calendar, the evening nudge stays quiet."
                )
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            calendarSourceRow(
                title: "Apple Calendar",
                detail: "Meetings stay on this iPhone",
                status: appleStatus,
                isReady: appleReady,
                actionTitle: appleReady ? nil : appleActionTitle,
                busy: false
            ) {
                await connectApple()
            }

            calendarSourceRow(
                title: "Google Calendar",
                detail: "Reads today’s meetings only",
                status: googleStatus,
                isReady: googleReady,
                actionTitle: googleReady ? "Disconnect" : "Connect",
                actionIsDestructive: googleReady,
                busy: googleBusy
            ) {
                if googleReady {
                    await disconnectGoogle()
                } else {
                    await connectGoogle()
                }
            }

            calendarNudgePreview
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    /// Included in TestFlight so Google reviewers can demo the evening nudge without waiting until 8:00 PM.
    private var calendarNudgePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.hairline)
            Text("Preview for reviewers")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Fires the same evening nudge in ~5 seconds from live calendar data — for screen recording without waiting until 8:00 PM.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await runCalendarNudgePreview() }
            } label: {
                HStack {
                    if previewBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(previewBusy ? "Finding someone…" : "Preview evening nudge now")
                        .font(Theme.body(15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Theme.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(previewBusy || !anyCalendarReady)
            if let previewStatus {
                Text(previewStatus)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func runCalendarNudgePreview() async {
        previewBusy = true
        previewStatus = nil
        defer { previewBusy = false }
        let result = await NotificationService.scheduleImmediateCalendarNudgePreview(
            authorId: auth.userId,
            selfEmails: selfEmails
        )
        switch result {
        case .scheduled(let person, let meeting):
            previewStatus = "Notification in ~5s for \(person) (\(meeting)). Lock the phone or go Home so the banner is visible, then tap it."
        case .notificationsDenied:
            previewStatus = "Notifications are off — enable them first."
        case .noCalendar:
            previewStatus = "Connect Google Calendar (or Apple) first."
        case .noCandidate:
            previewStatus = "No strong candidate today. In Google Calendar, add a weekday 1:1 (or small meeting) with another attendee that starts before 8:00 PM, then try again."
        case .schedulingFailed:
            previewStatus = "Couldn't schedule the preview notification."
        }
    }

    private var appleActionTitle: String {
        switch CalendarMeetingService.accessState {
        case .denied, .restricted: return "Open Settings"
        default: return "Allow"
        }
    }

    private func calendarSourceRow(
        title: String,
        detail: String,
        status: String,
        isReady: Bool,
        actionTitle: String?,
        actionIsDestructive: Bool = false,
        busy: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    statusPill(status, ready: isReady)
                }
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            if let actionTitle {
                Button {
                    Task { await action() }
                } label: {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(actionTitle)
                            .font(Theme.body(14, weight: .semibold))
                    }
                }
                .foregroundStyle(actionIsDestructive ? Color.red.opacity(0.9) : Theme.coral)
                .disabled(busy)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    (actionIsDestructive ? Color.red.opacity(0.12) : Theme.coral.opacity(0.14)),
                    in: Capsule()
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func statusPill(_ text: String, ready: Bool) -> some View {
        Text(text)
            .font(Theme.body(11, weight: .semibold))
            .foregroundStyle(ready ? Color(hex: 0x1F6B3A) : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (ready ? Color(hex: 0x1F6B3A).opacity(0.14) : Theme.textTertiary.opacity(0.14)),
                in: Capsule()
            )
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(Theme.body(13))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            if showOpenSystemSettings {
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.coral)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Actions

    private var selfEmails: Set<String> {
        var emails = Set<String>()
        if let email = auth.currentProfile?.email?.lowercased() {
            emails.insert(email)
        }
        return emails
    }

    private func setFridayReminderEnabled(_ enabled: Bool) {
        fridayToggleTask?.cancel()
        fridayToggleEpoch += 1
        let epoch = fridayToggleEpoch
        errorMessage = nil
        showOpenSystemSettings = false
        fridayReminderEnabled = enabled

        fridayToggleTask = Task {
            if enabled {
                let failure = await NotificationService.enableFridayReminder()
                guard !Task.isCancelled, epoch == fridayToggleEpoch else { return }
                await MainActor.run {
                    if let failure {
                        errorMessage = message(for: failure, feature: "Friday reminders")
                        showOpenSystemSettings = failure == .notificationsDenied
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            guard epoch == fridayToggleEpoch else { return }
                            fridayReminderEnabled = false
                        }
                    }
                }
            } else {
                await NotificationService.disableFridayReminder()
            }
        }
    }

    private func setCalendarNudgeEnabled(_ enabled: Bool) {
        calendarToggleTask?.cancel()
        calendarToggleEpoch += 1
        let epoch = calendarToggleEpoch
        errorMessage = nil
        showOpenSystemSettings = false
        calendarNudgeEnabled = enabled

        calendarToggleTask = Task {
            if enabled {
                let failure = await NotificationService.enableCalendarGratitudeNudge(
                    authorId: auth.userId,
                    selfEmails: selfEmails
                )
                guard !Task.isCancelled, epoch == calendarToggleEpoch else { return }
                await MainActor.run {
                    calendarAccessTick += 1
                    if failure == .calendarDenied {
                        // Keep the preference on — connect Apple or Google below.
                        errorMessage = message(for: .calendarDenied, feature: "evening thank-you nudges")
                        showOpenSystemSettings = false
                    } else if let failure {
                        errorMessage = message(for: failure, feature: "evening thank-you nudges")
                        showOpenSystemSettings = failure == .notificationsDenied
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            guard epoch == calendarToggleEpoch else { return }
                            calendarNudgeEnabled = false
                        }
                    } else {
                        CalendarGratitudeBackgroundRefresh.schedule()
                    }
                }
            } else {
                await NotificationService.disableCalendarGratitudeNudge()
            }
        }
    }

    private func connectApple() async {
        errorMessage = nil
        showOpenSystemSettings = false
        switch CalendarMeetingService.accessState {
        case .denied, .restricted:
            showOpenSystemSettings = true
            errorMessage = "Apple Calendar is off for OpenThanks. Turn it on in iPhone Settings, or connect Google Calendar instead."
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
        default:
            let granted = await CalendarMeetingService.requestAccess()
            calendarAccessTick += 1
            if granted {
                await refreshCalendarNudge()
            } else {
                errorMessage = "Apple Calendar wasn’t allowed. You can connect Google Calendar instead."
                showOpenSystemSettings = CalendarMeetingService.accessState == .denied
                    || CalendarMeetingService.accessState == .restricted
            }
        }
    }

    private func connectGoogle() async {
        googleBusy = true
        errorMessage = nil
        showOpenSystemSettings = false
        defer { googleBusy = false }
        do {
            try await GoogleCalendarAuth.connect()
            calendarAccessTick += 1
            await refreshCalendarNudge()
        } catch {
            if !GoogleCalendarAuth.isUserCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func disconnectGoogle() async {
        googleBusy = true
        defer { googleBusy = false }
        await GoogleCalendarAuth.disconnect()
        calendarAccessTick += 1
        if calendarNudgeEnabled {
            await refreshCalendarNudge()
        }
        if !anyCalendarReady, calendarNudgeEnabled {
            errorMessage = "No calendar connected — the evening nudge won’t fire until you connect Apple or Google."
        }
    }

    private func refreshCalendarNudge() async {
        await NotificationService.refreshCalendarGratitudeNudgeIfEnabled(
            calendarNudgeEnabled,
            authorId: auth.userId,
            selfEmails: selfEmails
        )
        if calendarNudgeEnabled {
            CalendarGratitudeBackgroundRefresh.schedule()
        }
    }

    private func message(
        for failure: NotificationService.ReminderEnableFailure,
        feature: String
    ) -> String {
        switch failure {
        case .notificationsDenied:
            return "Notifications are off for OpenThanks. Enable them in iPhone Settings to get \(feature)."
        case .calendarDenied:
            return "Connect Apple Calendar or Google Calendar below so evening thank-you nudges can suggest someone."
        case .schedulingFailed:
            return "Couldn't schedule \(feature). Try again in a moment."
        }
    }
}

extension NotificationsSettingsView {
    /// Compact status line for the Settings list row.
    static func summarySubtitle(fridayOn: Bool, eveningOn: Bool) -> String {
        switch (fridayOn, eveningOn) {
        case (true, true): return "Friday + evening"
        case (true, false): return "Friday only"
        case (false, true): return "Evening only"
        case (false, false): return "All off"
        }
    }
}
