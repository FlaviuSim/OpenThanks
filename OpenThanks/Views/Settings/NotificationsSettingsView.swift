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
    /// After connecting a calendar without notification auth.
    @State private var showPostCalendarNotifications = false
    @State private var showServerSyncConsent = false
    @State private var pendingConsentAction: PendingCalendarAction?
    @State private var deletingCalendarData = false
    @State private var showDeleteCalendarConfirm = false
    /// Founder / DEBUG: sync depth + who the evening nudge would pull.
    @State private var calendarTroubleshootBusy = false
    @State private var calendarTroubleshootStatus: CalendarServerAPI.StatusResponse?
    @State private var calendarTroubleshootNudge: GratitudeNudge?
    @State private var calendarTroubleshootNote: String?
    @State private var calendarTroubleshootTask: Task<Void, Never>?

    private enum PendingCalendarAction {
        case apple
        case google
    }

    /// Visible in DEBUG builds and for internal accounts (e.g. flsimihaian@gmail.com).
    private var showCalendarTroubleshoot: Bool {
        #if DEBUG
        return true
        #else
        let email = (auth.currentProfile?.email ?? "").lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Analytics.internalEmails.contains(email)
        #endif
    }

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

                if anyCalendarReady {
                    serverSyncSection
                }

                if showCalendarTroubleshoot {
                    calendarTroubleshootSection
                }

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
        .onAppear {
            calendarAccessTick += 1
            if showCalendarTroubleshoot {
                startCalendarTroubleshoot(sendTest: false, repair: false)
            }
        }
        .onDisappear {
            calendarTroubleshootTask?.cancel()
            calendarTroubleshootTask = nil
            calendarTroubleshootBusy = false
            fridayToggleTask?.cancel()
            calendarToggleTask?.cancel()
        }
        .alert(CalendarServerSyncConsent.disclosureTitle, isPresented: $showServerSyncConsent) {
            Button("Agree & continue") {
                CalendarServerSyncConsent.recordConsent()
                let action = pendingConsentAction
                pendingConsentAction = nil
                Task {
                    switch action {
                    case .apple:
                        await connectAppleAfterConsent()
                        if googleReady {
                            // Existing Google Keychain sessions need a fresh OAuth for server tokens.
                            await connectGoogleAfterConsent()
                        }
                    case .google:
                        await connectGoogleAfterConsent()
                        if appleReady {
                            await AppleCalendarHistoryUploader.uploadIfNeeded(force: true)
                        }
                    case .none:
                        if appleReady {
                            await AppleCalendarHistoryUploader.uploadIfNeeded(force: true)
                        }
                        if googleReady {
                            await connectGoogleAfterConsent()
                        }
                    }
                }
            }
            Button("Not now", role: .cancel) {
                pendingConsentAction = nil
            }
        } message: {
            Text(CalendarServerSyncConsent.disclosureBody)
        }
        .confirmationDialog(
            "Delete calendar data from OpenThanks?",
            isPresented: $showDeleteCalendarConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete calendar data", role: .destructive) {
                Task { await deleteCalendarDataFromServer() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes synced events, notes, suggestions, and encrypted Google tokens from OpenThanks. Your calendars on this phone are not deleted.")
        }
        .sheet(isPresented: $showPostCalendarNotifications) {
            NavigationStack {
                NotificationPermissionView(
                    onFinished: {
                        showPostCalendarNotifications = false
                        calendarAccessTick += 1
                    },
                    pitch: .postCalendar,
                    analyticsSource: "post_calendar"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") {
                            PermissionPromptScheduler.shared.markNotificationPromptCompleted()
                            calendarNudgeEnabled = false
                            Task { await NotificationService.disableCalendarGratitudeNudge() }
                            showPostCalendarNotifications = false
                        }
                        .font(Theme.body(16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .syncAppAppearance()
            .presentationDetents([.large])
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
            .tint(Theme.primary)

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
                        ? (CalendarServerSyncConsent.hasConsented
                            ? "We’ll sync history (including notes) to suggest people to thank — never for ads."
                            : "Connect is on-device until you agree to server sync below.")
                        : "Connect Apple or Google so we can suggest someone to thank. Without a calendar, the evening nudge stays quiet."
                )
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            calendarSourceRow(
                title: "Apple Calendar",
                detail: CalendarServerSyncConsent.hasConsented
                    ? "History + notes upload in the background"
                    : "Permission on this device; sync needs consent",
                status: appleStatus,
                isReady: appleReady,
                actionTitle: appleReady ? nil : appleActionTitle,
                busy: false
            ) {
                await connectApple()
            }

            calendarSourceRow(
                title: "Google Calendar",
                detail: CalendarServerSyncConsent.hasConsented
                    ? "Server sync with encrypted tokens"
                    : "Readonly calendar access",
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
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
                .foregroundStyle(Theme.primary)
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
                let failure = await NotificationService.enableFridayReminder(analyticsSource: "settings")
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
                    selfEmails: selfEmails,
                    analyticsSource: "settings"
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

    private var serverSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenThanks sync")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(
                CalendarServerSyncConsent.hasConsented
                    ? "Server sync is on. History including meeting notes is used only for thank-you suggestions and drafts."
                    : "To suggest people from your calendar history (including notes), OpenThanks needs your consent to sync to our servers."
            )
            .font(Theme.body(13))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if !CalendarServerSyncConsent.hasConsented {
                Button("Review & enable sync") {
                    // Prefer re-auth Google so refresh tokens move to the server.
                    pendingConsentAction = googleReady ? .google : .apple
                    showServerSyncConsent = true
                }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.coral)
            } else {
                Button(deletingCalendarData ? "Deleting…" : "Delete calendar data from OpenThanks") {
                    showDeleteCalendarConfirm = true
                }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.9))
                .disabled(deletingCalendarData)
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

    private var calendarTroubleshootSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar troubleshoot")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Internal only. Shows sync depth, top people from history, and who tonight’s nudge would pull — then can fire a test notification in ~3s.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = calendarTroubleshootStatus {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Synced events: \(status.eventCount) · people: \(status.peopleCount)")
                    Text(calendarHistoryDepthLine(status))
                    ForEach(status.connections, id: \.provider) { conn in
                        Text(
                            "\(conn.provider): \(conn.backfill_status)"
                                + (conn.last_synced_at.map { " · last \($0)" } ?? "")
                                + (conn.last_error.map { " · err \($0)" } ?? "")
                        )
                    }
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)

                if let people = status.peopleSample, !people.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top people by meetings")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(people.prefix(8)) { person in
                            let name = trimmedNonEmpty(person.display_name)
                                ?? trimmedNonEmpty(person.email)
                                ?? "(unnamed)"
                            let first = shortISODate(person.first_seen_at)
                            let last = shortISODate(person.last_seen_at)
                            Text(
                                "· \(name) — \(person.meeting_count ?? 0) mtgs"
                                    + (first.map { " · from \($0)" } ?? "")
                                    + (last.map { " → \($0)" } ?? "")
                            )
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .textSelection(.enabled)
                }
            } else if calendarTroubleshootBusy {
                ProgressView()
                    .controlSize(.small)
            }

            if let nudge = calendarTroubleshootNudge {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tonight’s candidate")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(nudge.personName)" + (nudge.email.map { " · \($0)" } ?? ""))
                    Text("Meeting: \(nudge.meetingTitle)")
                    if !nudge.reason.isEmpty {
                        Text("Reason: \(nudge.reason)")
                    }
                    if let draft = nudge.messageDraft, !draft.isEmpty {
                        Text("Draft: \(draft)")
                            .lineLimit(4)
                    }
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            }

            if let calendarTroubleshootNote {
                Text(calendarTroubleshootNote)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    startCalendarTroubleshoot(sendTest: false, repair: true)
                } label: {
                    Text(calendarTroubleshootBusy ? "Repairing…" : "Repair & refresh")
                        .font(Theme.body(14, weight: .semibold))
                }
                .disabled(calendarTroubleshootBusy)

                Button {
                    startCalendarTroubleshoot(sendTest: true, repair: false)
                } label: {
                    Text("Send test notification")
                        .font(Theme.body(14, weight: .semibold))
                }
                .disabled(calendarTroubleshootBusy)
            }
            .foregroundStyle(Theme.coral)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.coral.opacity(0.35), lineWidth: 1)
        )
    }

    private func calendarHistoryDepthLine(_ status: CalendarServerAPI.StatusResponse) -> String {
        let earliest = shortISODate(status.earliestEventAt)
        let latest = shortISODate(status.latestEventAt)
        switch (earliest, latest) {
        case let (e?, l?):
            return "History range: \(e) → \(l)"
        case (nil, nil) where status.eventCount == 0:
            return "History range: no synced events yet (backfill still running or not connected)."
        default:
            return "History range: unavailable (redeploy status API for earliest/latest)."
        }
    }

    private func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func shortISODate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let date = isoFrac.date(from: raw) ?? iso.date(from: raw)
        guard let date else {
            return String(raw.prefix(10))
        }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    private func startCalendarTroubleshoot(sendTest: Bool, repair: Bool) {
        calendarTroubleshootTask?.cancel()
        calendarTroubleshootTask = Task { @MainActor in
            await refreshCalendarTroubleshoot(sendTest: sendTest, repair: repair)
        }
    }

    private func refreshCalendarTroubleshoot(sendTest: Bool, repair: Bool) async {
        calendarTroubleshootBusy = true
        calendarTroubleshootNote = nil
        defer {
            calendarTroubleshootBusy = false
        }

        var repairNote: String?

        // Server repair first — never wait on a 10-year Apple upload before this returns.
        if repair, CalendarServerSyncConsent.hasConsented {
            calendarTroubleshootNote = "Repairing server sync…"
            do {
                let result = try await CalendarServerAPI.repair()
                try Task.checkCancellation()
                let people = result.people ?? 0
                let synced = result.googleSynced ?? 0
                let reset = result.googleReset ?? 0
                repairNote = "Repair: reset \(reset), synced \(synced), people \(people)"
                    + (result.suggested == true ? ", suggestion ready" : "")
                if let errors = result.errors, !errors.isEmpty {
                    repairNote! += " · \(errors.prefix(2).joined(separator: "; "))"
                }
                calendarTroubleshootNote = repairNote
            } catch is CancellationError {
                return
            } catch {
                repairNote = "Repair failed: \(error.localizedDescription)"
                calendarTroubleshootNote = repairNote
            }
        }

        do {
            calendarTroubleshootStatus = try await CalendarServerAPI.status()
        } catch is CancellationError {
            return
        } catch {
            calendarTroubleshootStatus = nil
            calendarTroubleshootNote = repairNote.map { "\($0) · Status failed: \(error.localizedDescription)" }
                ?? "Status failed: \(error.localizedDescription)"
        }

        try? Task.checkCancellation()
        let nudge = await CalendarThankSuggestionService.resolveNudge(
            for: Date(),
            authorId: auth.userId,
            selfEmails: selfEmails,
            now: Date()
        )
        guard !Task.isCancelled else { return }
        calendarTroubleshootNudge = nudge

        // Apple history must not pin the button on “Repairing…”.
        // Open/refresh: soft upload in the background. Repair: time-boxed force upload.
        if CalendarServerSyncConsent.hasConsented, CalendarMeetingService.hasFullAccess {
            if repair {
                calendarTroubleshootNote = (repairNote.map { "\($0) · " } ?? "")
                    + "Uploading Apple history…"
                let finished = await withTimeout(seconds: 75) {
                    await AppleCalendarHistoryUploader.uploadIfNeeded(force: true)
                }
                guard !Task.isCancelled else { return }
                if !finished {
                    Task.detached(priority: .utility) {
                        await AppleCalendarHistoryUploader.uploadIfNeeded(force: true)
                    }
                    repairNote = (repairNote ?? "Repair done")
                        + " · Apple upload continuing in background"
                } else if let status = try? await CalendarServerAPI.status() {
                    calendarTroubleshootStatus = status
                }
            } else {
                Task.detached(priority: .utility) {
                    await AppleCalendarHistoryUploader.uploadIfNeeded(force: false)
                }
            }
        }

        guard sendTest else {
            if let repairNote {
                calendarTroubleshootNote = repairNote
                    + (nudge == nil ? " · No candidate yet (backfill may need another cron pass)." : "")
            } else if nudge == nil, calendarTroubleshootNote == nil {
                calendarTroubleshootNote = "No candidate resolved yet."
            }
            return
        }

        let result = await NotificationService.scheduleTestCalendarNudge(
            authorId: auth.userId,
            selfEmails: selfEmails
        )
        guard !Task.isCancelled else { return }
        if let sent = result.nudge {
            calendarTroubleshootNudge = sent
            calendarTroubleshootNote = "Test notification queued — lock the phone or wait ~3s."
        } else {
            calendarTroubleshootNote = result.error ?? "Couldn't schedule the test notification."
        }
    }

    /// Returns `true` when `operation` finished before the timeout.
    private func withTimeout(seconds: TimeInterval, operation: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await operation()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 1) * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func connectApple() async {
        if !CalendarServerSyncConsent.hasConsented {
            pendingConsentAction = .apple
            showServerSyncConsent = true
            return
        }
        await connectAppleAfterConsent()
    }

    private func connectAppleAfterConsent() async {
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
            let granted = await CalendarMeetingService.requestAccess(analyticsSource: "settings")
            calendarAccessTick += 1
            if granted {
                await AppleCalendarHistoryUploader.uploadIfNeeded(force: true)
                await finishSettingsCalendarConnect()
            } else {
                errorMessage = "Apple Calendar wasn’t allowed. You can connect Google Calendar instead."
                showOpenSystemSettings = CalendarMeetingService.accessState == .denied
                    || CalendarMeetingService.accessState == .restricted
            }
        }
    }

    private func connectGoogle() async {
        if !CalendarServerSyncConsent.hasConsented {
            pendingConsentAction = .google
            showServerSyncConsent = true
            return
        }
        await connectGoogleAfterConsent()
    }

    private func connectGoogleAfterConsent() async {
        googleBusy = true
        errorMessage = nil
        showOpenSystemSettings = false
        defer { googleBusy = false }
        do {
            try await GoogleCalendarAuth.connect(analyticsSource: "settings")
            calendarAccessTick += 1
            await finishSettingsCalendarConnect()
        } catch {
            if !GoogleCalendarAuth.isUserCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteCalendarDataFromServer() async {
        deletingCalendarData = true
        defer { deletingCalendarData = false }
        do {
            try await CalendarServerAPI.disconnect()
            CalendarServerSyncConsent.revoke()
            UserDefaults.standard.removeObject(forKey: "appleCalendarHistoryUploader.lastDoneAt")
            await GoogleCalendarAuth.disconnect()
            calendarAccessTick += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Calendar alone isn’t enough for evening nudges — prompt for notifications when needed.
    private func finishSettingsCalendarConnect() async {
        PermissionPromptScheduler.shared.markCalendarPromptCompleted()
        if await NotificationService.isAuthorized() {
            await refreshCalendarNudge()
            return
        }
        calendarNudgeEnabled = false
        await NotificationService.disableCalendarGratitudeNudge()
        showPostCalendarNotifications = true
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
