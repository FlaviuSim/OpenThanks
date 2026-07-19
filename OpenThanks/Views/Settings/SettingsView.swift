import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCount = 0
    @State private var showEditProfile = false
    @State private var notificationError: String?
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue

    private var lightModeEnabled: Binding<Bool> {
        Binding(
            get: { appearance == AppAppearance.light.rawValue },
            set: { appearance = $0 ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
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
                    Link(destination: URL(string: "https://openthanks.com/privacy")!) {
                        rowLabel("Privacy")
                    }
                    Link(destination: URL(string: "https://openthanks.com/terms")!) {
                        rowLabel("Terms of Service")
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Notifications") {
                    Toggle(isOn: $fridayReminderEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Friday Gratitude Reminder")
                            Text("Every Friday at 9:00 AM")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.coral)

                    if let notificationError {
                        Text(notificationError)
                            .font(Theme.body(12))
                            .foregroundStyle(.red)
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
            .onChange(of: fridayReminderEnabled) { _, enabled in
                notificationError = nil
                Task {
                    if enabled {
                        let didEnable = await NotificationService.enableFridayReminder()
                        if !didEnable {
                            fridayReminderEnabled = false
                            notificationError = "Notifications are off. Enable them in Settings to get Friday reminders."
                        }
                    } else {
                        await NotificationService.disableFridayReminder()
                    }
                }
            }
            .task {
                guard let userId = auth.userId else { return }
                pendingCount = (try? await GratitudeService.pending(authorId: userId).count) ?? 0
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        HStack { Text(text).foregroundStyle(Theme.textPrimary); Spacer() }
    }
}

struct EditProfileSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var required = false
    @State private var fullName = ""
    @State private var username = ""
    @State private var headline = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var nonprofitEin: String?
    @State private var nonprofitName: String?
    @State private var nonprofitWebsite: String?
    @State private var nonprofitWhy = ""
    @State private var nonprofitQuery = ""
    @State private var nonprofitResults: [NonprofitOrg] = []
    @State private var searching = false
    @State private var saving = false
    @State private var errorMessage: String?

    private var cleanUsername: String {
        username.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private var cleanFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAvatar: Bool {
        photoData != nil || auth.currentProfile?.avatarURL != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    profilePhotoRow
                    TextField("Full name", text: $fullName)
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(Theme.textSecondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !required {
                        TextField("Headline", text: $headline)
                    }
                }
                .listRowBackground(Theme.surface)

                if !required {
                    nonprofitSection
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(Theme.body(13))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Theme.surface)
                }

                if required {
                    Section {
                        Text("Add your name, username, and a profile photo before entering OpenThanks.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(required ? "Complete Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !required {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(required ? "Continue" : "Save") { Task { await save() } }
                        .disabled(saving || cleanUsername.isEmpty || cleanFullName.isEmpty || !hasAvatar)
                        .foregroundStyle(Theme.coral)
                }
            }
            .onAppear {
                let p = auth.currentProfile
                fullName = p?.fullName ?? ""
                username = p?.username ?? ""
                headline = p?.headline ?? ""
                nonprofitEin = p?.favoriteNonprofitEin
                nonprofitName = p?.favoriteNonprofitName
                nonprofitWebsite = p?.favoriteNonprofitWebsite
                nonprofitWhy = p?.favoriteNonprofitHeadline ?? ""
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    photoData = try? await item.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private var profilePhotoRow: some View {
        VStack(spacing: 12) {
            Group {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let avatarURL = auth.currentProfile?.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.heartGradient, lineWidth: 2))
            .frame(maxWidth: .infinity)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(hasAvatar ? "Change Profile Photo" : "Add Profile Photo")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Theme.surfaceRaised)
            Image(systemName: "person.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var nonprofitSection: some View {
        Section("Nonprofit you champion") {
            if let nonprofitName {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nonprofitName)
                            .font(Theme.body(15, weight: .semibold))
                        if let nonprofitEin {
                            Text("EIN \(nonprofitEin)")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        self.nonprofitName = nil
                        nonprofitEin = nil
                        nonprofitWebsite = nil
                        nonprofitWhy = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                TextField("Why this cause? (shown on your profile)",
                          text: $nonprofitWhy, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                HStack {
                    TextField("Search nonprofits…", text: $nonprofitQuery)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await searchNonprofits() } }
                    Button {
                        Task { await searchNonprofits() }
                    } label: {
                        if searching {
                            ProgressView().tint(Theme.coral)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.coral)
                        }
                    }
                    .disabled(nonprofitQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(nonprofitResults.prefix(8)) { org in
                    Button {
                        nonprofitEin = org.strein
                        nonprofitName = org.name
                        nonprofitWebsite = org.website
                        nonprofitResults = []
                        nonprofitQuery = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(org.name)
                                .font(Theme.body(14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            if let location = org.location {
                                Text(location)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func searchNonprofits() async {
        let query = nonprofitQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searching = true
        nonprofitResults = (try? await GratitudeService.searchNonprofits(query: query)) ?? []
        searching = false
    }

    private func save() async {
        guard let userId = auth.userId else { return }
        saving = true
        errorMessage = nil
        do {
            var avatarURLString = auth.currentProfile?.avatarUrl
            if let photoData {
                guard let image = UIImage(data: photoData),
                      let jpegData = image.jpegData(compressionQuality: 0.85) else {
                    throw URLError(.cannotDecodeContentData)
                }
                avatarURLString = try await GratitudeService.uploadAvatar(
                    data: jpegData,
                    contentType: "image/jpeg",
                    userId: userId
                ).absoluteString
            }
            let update: GratitudeService.ProfileUpdate
            if required {
                update = .init(
                    fullName: cleanFullName,
                    username: cleanUsername,
                    avatarUrl: avatarURLString
                )
            } else {
                update = .init(
                    fullName: cleanFullName,
                    username: cleanUsername,
                    avatarUrl: avatarURLString,
                    headline: headline.isEmpty ? nil : headline,
                    favoriteNonprofitEin: nonprofitEin,
                    favoriteNonprofitName: nonprofitName,
                    favoriteNonprofitWebsite: nonprofitWebsite,
                    favoriteNonprofitHeadline: nonprofitName == nil || nonprofitWhy.isEmpty
                        ? nil : nonprofitWhy,
                    clearOptionalFields: true
                )
            }
            let updated = try await GratitudeService.updateProfile(userId: userId, update: update)
            auth.currentProfile = updated
            if !required { dismiss() }
        } catch {
            errorMessage = error.localizedDescription.localizedCaseInsensitiveContains("duplicate")
                || error.localizedDescription.localizedCaseInsensitiveContains("unique")
                ? "That username is already taken."
                : error.localizedDescription
        }
        saving = false
    }
}

struct PendingAppreciationsView: View {
    @Environment(AuthService.self) private var auth
    @State private var pending: [Gratitude] = []
    @State private var sharing: Gratitude?
    @State private var editing: Gratitude?
    @State private var deleting: Gratitude?
    @State private var busyId: UUID?
    @State private var errorMessage: String?

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
        }
        .background(Theme.background)
        .navigationTitle("Pending Appreciations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharing) { g in
            PendingShareSheet(gratitude: g)
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: $editing) { g in
            ComposeView(editing: g) { updated in
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
            Text("This pending appreciation will be removed permanently. The claim link will stop working.")
        }
        .task { await reload() }
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
                        Text(g.message)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        Text("Pending — tap to share the claim link")
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
                Label("Share claim link", systemImage: "square.and.arrow.up")
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
