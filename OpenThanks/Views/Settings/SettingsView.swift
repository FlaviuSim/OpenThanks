import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCount = 0
    @State private var showEditProfile = false
    @State private var notificationError: String?
    @State private var showOpenSystemSettings = false
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue
    @State private var calendarAccessTick = 0
    /// Serializes toggle work so rapid taps can't leave AppStorage fighting the Toggle.
    @State private var fridayToggleTask: Task<Void, Never>?
    @State private var calendarToggleTask: Task<Void, Never>?
    @State private var fridayToggleEpoch = 0
    @State private var calendarToggleEpoch = 0

    private var calendarAccessLabel: String {
        _ = calendarAccessTick
        switch CalendarMeetingService.accessState {
        case .fullAccess: return "Allowed"
        case .writeOnly: return "Write only — needs full access"
        case .denied, .restricted: return "Off"
        case .notDetermined: return "Not set"
        }
    }

    private var lightModeEnabled: Binding<Bool> {
        Binding(
            get: { appearance == AppAppearance.light.rawValue },
            set: { appearance = $0 ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue }
        )
    }

    private var fridayReminderBinding: Binding<Bool> {
        Binding(
            get: { fridayReminderEnabled },
            set: { setFridayReminderEnabled($0) }
        )
    }

    private var calendarNudgeBinding: Binding<Bool> {
        Binding(
            get: { calendarNudgeEnabled },
            set: { setCalendarNudgeEnabled($0) }
        )
    }

    private var feedbackMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "flaviu@openthanks.com"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "OpenThanks feedback"),
            URLQueryItem(
                name: "body",
                value: "\n\n—\nApp version \(version) (\(build))"
            ),
        ]
        return components.url ?? URL(string: "mailto:flaviu@openthanks.com")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button { showEditProfile = true } label: { rowLabel("Edit Profile") }
                    NavigationLink {
                        StatsView()
                    } label: {
                        rowLabel("Your Stats")
                    }
                    NavigationLink {
                        PendingAppreciationsView()
                    } label: {
                        HStack {
                            Text("Pending Appreciations")
                            Spacer()
                            if pendingCount > 0 {
                                Text("\(pendingCount)")
                                    .font(Theme.body(13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Theme.coral, in: Capsule())
                            }
                        }
                    }
                    Link(destination: URL(string: "https://openthanks.com/privacy")!) {
                        rowLabel("Privacy")
                    }
                    Link(destination: URL(string: "https://openthanks.com/terms")!) {
                        rowLabel("Terms of Service")
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Notifications") {
                    Toggle(isOn: fridayReminderBinding) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Friday Gratitude Reminder")
                            Text("Every Friday at 9:00 AM — a gentle prompt.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.coral)

                    Toggle(isOn: calendarNudgeBinding) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Evening Thank-You Nudge")
                            Text("Weekdays at 8:00 PM when your Calendar suggests someone to thank. 100% private—your calendar data never leaves your device.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.coral)

                    if calendarNudgeEnabled {
                        HStack {
                            Text("Calendar access")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(calendarAccessLabel)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if CalendarMeetingService.accessState != .fullAccess {
                            Button("Allow Calendar") {
                                Task {
                                    let granted = await CalendarMeetingService.requestAccess()
                                    calendarAccessTick += 1
                                    if granted {
                                        await refreshCalendarNudge()
                                        notificationError = nil
                                        showOpenSystemSettings = false
                                    } else {
                                        notificationError = "Calendar access is required for evening thank-you nudges. Enable it in iPhone Settings → OpenThanks."
                                        showOpenSystemSettings = true
                                    }
                                }
                            }
                            .foregroundStyle(Theme.coral)
                        }
                    }

                    if let notificationError {
                        Text(notificationError)
                            .font(Theme.body(12))
                            .foregroundStyle(.red)

                        if showOpenSystemSettings {
                            Button("Open iPhone Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Support OpenThanks") {
                    Link(destination: URL(string: "https://buy.stripe.com/3cIcN67Z6cYO3erfyJcZa00")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Support OpenThanks")
                                Text("Subscribe and help keep OpenThanks ad-free and growing.")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "heart.fill").foregroundStyle(Theme.coral)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("App") {
                    Toggle(isOn: lightModeEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Light Mode")
                            Text("Use a brighter appearance across the app.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.coral)

                    Link(destination: feedbackMailURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Send Feedback")
                            Text("Email us at flaviu@openthanks.com")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    HStack {
                        Text("About OpenThanks")
                        Spacer()
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button(role: .destructive) {
                        dismiss()
                        Task { await auth.signOut() }
                    } label: {
                        Text("Log Out").foregroundStyle(.red)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .foregroundStyle(Theme.textPrimary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.coral)
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet()
                    .syncAppAppearance()
            }
            .syncAppAppearance()
            .task {
                guard let userId = auth.userId else { return }
                pendingCount = (try? await GratitudeService.pendingCount(authorId: userId)) ?? 0
                calendarAccessTick += 1
            }
            .onDisappear {
                fridayToggleTask?.cancel()
                calendarToggleTask?.cancel()
            }
        }
    }

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
        notificationError = nil
        showOpenSystemSettings = false
        fridayReminderEnabled = enabled

        fridayToggleTask = Task {
            if enabled {
                let failure = await NotificationService.enableFridayReminder()
                guard !Task.isCancelled, epoch == fridayToggleEpoch else { return }
                await MainActor.run {
                    if let failure {
                        notificationError = message(for: failure, feature: "Friday reminders")
                        showOpenSystemSettings = failure == .notificationsDenied
                        // Let the Toggle finish its on animation before reverting —
                        // reverting inside the same turn can leave the control stuck off.
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
        notificationError = nil
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
                    if let failure {
                        notificationError = message(for: failure, feature: "evening thank-you nudges")
                        showOpenSystemSettings = true
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

    private func message(
        for failure: NotificationService.ReminderEnableFailure,
        feature: String
    ) -> String {
        switch failure {
        case .notificationsDenied:
            return "Notifications are off. Enable them in iPhone Settings to get \(feature)."
        case .calendarDenied:
            return "Calendar access is required for evening thank-you nudges. Enable it in iPhone Settings → OpenThanks."
        case .schedulingFailed:
            return "Couldn't schedule \(feature). Try again in a moment."
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

    private func rowLabel(_ text: String) -> some View {
        HStack { Text(text).foregroundStyle(Theme.textPrimary); Spacer() }
    }
}

struct PendingAppreciationsView: View {
    @Environment(AuthService.self) private var auth
    /// When opened from an author-reminder link (`?resend=`), open that item's share sheet.
    var highlightId: UUID? = nil
    @State private var pending: [Gratitude] = []
    @State private var sharing: Gratitude?
    @State private var editing: Gratitude?
    @State private var deleting: Gratitude?
    @State private var busyId: UUID?
    @State private var errorMessage: String?
    @State private var didApplyHighlight = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if pending.isEmpty {
                    Text("No pending appreciations. Everything you've sent has been claimed.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 48)
                        .padding(.horizontal, 32)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(13))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                ForEach(pending) { g in
                    pendingCard(g)
                }
            }
            .padding(16)
            // Clear the floating tab bar so Edit / Share / Delete stay tappable.
            .tabChromeBottomPadding()
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle("Pending Appreciations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharing) { g in
            PendingShareSheet(gratitude: g)
                .presentationDetents([.medium])
        }
        .composeCover(item: $editing) { g in
            ComposeView(editing: g, analyticsSource: "edit_pending") { updated in
                if let index = pending.firstIndex(where: { $0.id == updated.id }) {
                    pending[index] = updated
                }
            }
        }
        .confirmationDialog(
            "Delete this appreciation?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    Task { await delete(deleting) }
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("This pending appreciation will be removed permanently. The link to accept will stop working.")
        }
        .task { await reload() }
    }

    private func applyHighlightIfNeeded() {
        guard !didApplyHighlight, let highlightId else { return }
        didApplyHighlight = true
        if let match = pending.first(where: { $0.id == highlightId }) {
            sharing = match
        }
    }

    private func pendingCard(_ g: Gratitude) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { sharing = g } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "clock")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.surfaceRaised, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To: \(g.recipientDisplayName)")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let contact = g.recipientEmail ?? g.recipientPhone {
                            Text(contact)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        LinkifiedText(
                            text: g.message,
                            font: Theme.body(13),
                            foreground: Theme.textSecondary
                        )
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        Text("Pending — tap to share the link to accept")
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                    Spacer(minLength: 0)
                    if let date = g.createdAt {
                        Text(date, format: .relative(presentation: .named))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                actionButton(title: "Edit", systemImage: "square.and.pencil") {
                    editing = g
                }
                actionButton(title: "Share", systemImage: "link") {
                    sharing = g
                }
                actionButton(title: "Delete", systemImage: "trash", destructive: true) {
                    deleting = g
                }
                if busyId == g.id {
                    ProgressView()
                        .tint(Theme.coral)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(14)
        .card()
        .contextMenu {
            Button { sharing = g } label: {
                Label("Share link to accept", systemImage: "square.and.arrow.up")
            }
            Button { editing = g } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { deleting = g } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                Text(title)
                    .font(Theme.body(13, weight: .semibold))
            }
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busyId != nil)
    }

    private func reload() async {
        guard let userId = auth.userId else { return }
        pending = (try? await GratitudeService.pending(authorId: userId)) ?? []
        applyHighlightIfNeeded()
    }

    private func delete(_ gratitude: Gratitude) async {
        busyId = gratitude.id
        errorMessage = nil
        defer {
            busyId = nil
            deleting = nil
        }
        do {
            try await GratitudeService.delete(id: gratitude.id)
            withAnimation {
                pending.removeAll { $0.id == gratitude.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
