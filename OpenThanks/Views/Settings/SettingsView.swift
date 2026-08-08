import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCount = 0
    @State private var showEditProfile = false
    @State private var showDeleteAccountConfirm = false
    @State private var deletingAccount = false
    @State private var deleteAccountError: String?
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue

    private var appearanceSubtitle: String {
        (AppAppearance(rawValue: appearance) ?? .dark).title
    }

    private var notificationsSubtitle: String {
        NotificationsSettingsView.summarySubtitle(
            fridayOn: fridayReminderEnabled,
            eveningOn: calendarNudgeEnabled
        )
    }

    private var accountSectionTitle: String {
        let email = auth.currentProfile?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let email, !email.isEmpty {
            return "Account (\(email))"
        }
        return "Account"
    }

    private var feedbackMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "founders@openthanks.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "OpenThanks feedback"),
            URLQueryItem(name: "body", value: feedbackMailBody),
        ]
        return components.url ?? URL(string: "mailto:founders@openthanks.com")!
    }

    /// Pre-filled draft: blank space for the note, then diagnostics for support.
    private var feedbackMailBody: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let system = "\(device.systemName) \(device.systemVersion)"
        let model = deviceModelIdentifier
        let appearanceTitle = (AppAppearance(rawValue: appearance) ?? .dark).title
        let locale = Locale.current.identifier
        let email = auth.currentProfile?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = auth.currentProfile?.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = auth.userId?.uuidString

        var lines: [String] = [
            "",
            "",
            "—",
            "Please keep this info — it helps us debug:",
            "App: OpenThanks \(version) (\(build))",
            "Bundle: \(bundleId)",
            "Device: \(model)",
            "System: \(system)",
            "Appearance: \(appearanceTitle)",
            "Locale: \(locale)",
        ]
        if let handle, !handle.isEmpty {
            lines.append("Handle: @\(handle)")
        }
        if let email, !email.isEmpty {
            lines.append("Account email: \(email)")
        }
        if let userId {
            lines.append("User ID: \(userId)")
        }
        return lines.joined(separator: "\n")
    }

    /// Hardware identifier (e.g. iPhone15,2) — more useful than the marketing name.
    private var deviceModelIdentifier: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    var body: some View {
        NavigationStack {
            List {
                Section(accountSectionTitle) {
                    Button { showEditProfile = true } label: { rowLabel("Edit Profile") }
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
                    NavigationLink {
                        StatsView()
                    } label: {
                        rowLabel("Your Stats")
                    }
                    NavigationLink {
                        LoggingInView()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Logging In")
                            Text("Email, Google, phone, and passkeys")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("App") {
                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Notifications")
                                Text("Reminders and calendar suggestions")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(notificationsSubtitle)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    NavigationLink {
                        AppearanceView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Appearance")
                                Text("Theme and app icon")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(appearanceSubtitle)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Link(destination: feedbackMailURL) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Send Feedback")
                                Text("Email us at founders@openthanks.com")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Link(destination: URL(string: "https://buy.stripe.com/aFadR826I06Ea0i14l1ZS00")!) {
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

                    HStack(spacing: 6) {
                        Link("Privacy", destination: URL(string: "https://openthanks.com/privacy")!)
                        Text("·")
                            .foregroundStyle(Theme.textTertiary)
                        Link("Terms of Service", destination: URL(string: "https://openthanks.com/terms")!)
                        Spacer()
                    }
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.textPrimary)

                    Button(role: .destructive) {
                        dismiss()
                        Task { await auth.signOut() }
                    } label: {
                        Text("Log Out").foregroundStyle(.red)
                    }

                    Button(role: .destructive) {
                        deleteAccountError = nil
                        showDeleteAccountConfirm = true
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(deletingAccount ? "Deleting Account…" : "Delete Account")
                                .foregroundStyle(.red)
                            Text("Permanently deletes your profile and appreciations")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .disabled(deletingAccount)

                    if let deleteAccountError {
                        Text(deleteAccountError)
                            .font(Theme.body(13))
                            .foregroundStyle(.red)
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
            .confirmationDialog(
                "Delete your OpenThanks account?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, profile, and appreciations. This can’t be undone.")
            }
            .syncAppAppearance()
            .task {
                guard let userId = auth.userId else { return }
                pendingCount = (try? await GratitudeService.pendingCount(authorId: userId)) ?? 0
            }
        }
    }

    private func performDeleteAccount() async {
        deletingAccount = true
        deleteAccountError = nil
        let ok = await auth.deleteAccount()
        deletingAccount = false
        if ok {
            dismiss()
        } else {
            deleteAccountError = auth.errorMessage
                ?? "Couldn't delete your account. Please try again or email founders@openthanks.com."
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
