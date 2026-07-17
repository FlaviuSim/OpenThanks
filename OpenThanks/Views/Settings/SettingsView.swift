import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCount = 0
    @State private var showEditProfile = false
    @State private var notificationError: String?
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = false
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
                ForEach(pending) { g in
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
                                    .lineLimit(2)
                                Text("Pending — tap to send the claim link")
                                    .font(Theme.body(12, weight: .semibold))
                                    .foregroundStyle(Theme.coral)
                            }
                            Spacer()
                            if let date = g.createdAt {
                                Text(date, format: .relative(presentation: .named))
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .card()
                    }
                    .buttonStyle(.plain)
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
        .task {
            guard let userId = auth.userId else { return }
            pending = (try? await GratitudeService.pending(authorId: userId)) ?? []
        }
    }
}

/// Actions for nudging a recipient: copy the claim link, or jump to
/// Messages with a pre-drafted text containing it.
struct PendingShareSheet: View {
    let gratitude: Gratitude
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var messageBody: String {
        let name = gratitude.recipientName?.split(separator: " ").first.map(String.init)
        let greeting = name.map { "Hey \($0)! " } ?? "Hey! "
        let link = gratitude.claimURL?.absoluteString ?? AppConfig.webAppURL.absoluteString
        return greeting + "I wrote you an appreciation on OpenThanks 💛 You can read and claim it here: " + link
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(Theme.hairline).frame(width: 36, height: 4)
                .padding(.top, 10)

            VStack(spacing: 6) {
                Text("Nudge \(gratitude.recipientDisplayName)")
                    .font(Theme.display(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("They haven't claimed your appreciation yet. Send them the link directly.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if let claimURL = gratitude.claimURL {
                Text(claimURL.absoluteString)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                Button {
                    let recipient = gratitude.recipientPhone ?? ""
                    let encoded = messageBody.addingPercentEncoding(
                        withAllowedCharacters: .alphanumerics) ?? ""
                    if let url = URL(string: "sms:\(recipient)&body=\(encoded)") {
                        openURL(url)
                    }
                } label: {
                    Label("Send via Messages", systemImage: "message.fill")
                }
                .buttonStyle(CTAButtonStyle())

                Button {
                    UIPasteboard.general.string = gratitude.claimURL?.absoluteString
                        ?? messageBody
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Link copied" : "Copy link",
                          systemImage: copied ? "checkmark" : "link")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(copied ? Theme.coral : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surfaceRaised, in: Capsule())
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}
