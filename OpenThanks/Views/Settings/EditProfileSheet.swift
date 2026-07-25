import SwiftUI
import PhotosUI

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

    // Phone (auth-confirmed) — add / change / remove mirrors web edit profile.
    @State private var verifiedPhone: String?
    @State private var accountEmail: String?
    @State private var phoneInput = ""
    @State private var phoneCode = ""
    @State private var phoneCodeSent = false
    @State private var phoneBusy = false
    @State private var phoneError: String?
    @State private var phoneSuccess: String?

    private var cleanUsername: String {
        username.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private var cleanFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAvatar: Bool {
        photoData != nil || auth.currentProfile?.avatarURL != nil
    }

    private var phoneChanged: Bool {
        AuthService.normalizedPhone(phoneInput) != verifiedPhone
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
                    phoneSection
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
                        Text("Add your name and username to enter OpenThanks. A profile photo is optional.")
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
                        .disabled(saving || cleanUsername.isEmpty || cleanFullName.isEmpty)
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
                Task { await loadPhoneState() }
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
                    CachedAsyncImage(url: avatarURL) { image in
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
                Text(hasAvatar ? "Change Profile Photo" : "Add Profile Photo (optional)")
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
                        if let nonprofitEin, nonprofitEin != "custom" {
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
                TextField(
                    "Nonprofit website",
                    text: Binding(
                        get: { nonprofitWebsite ?? "" },
                        set: { nonprofitWebsite = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .onSubmit { normalizeNonprofitWebsite() }
                TextField(
                    "Why this cause? (shown on your profile)",
                    text: $nonprofitWhy,
                    axis: .vertical
                )
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
                        // Match web: user enters the org's own site (not ProPublica).
                        nonprofitWebsite = ""
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

    @ViewBuilder
    private var phoneSection: some View {
        Section {
            if phoneCodeSent {
                Text(phoneInput)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                OneTimeCodeField(text: $phoneCode, isFocused: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .onChange(of: phoneCode) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { phoneCode = digits }
                        guard digits.count == 6, !phoneBusy else { return }
                        Task { await verifyPhone() }
                    }
                if phoneBusy {
                    ProgressView().tint(Theme.coral)
                } else {
                    Button("Verify code") { Task { await verifyPhone() } }
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .disabled(phoneCode.count < 6)
                    Button("Cancel") { cancelPhoneChange() }
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if let verifiedPhone {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verifiedPhone)
                            .font(Theme.body(15, weight: .semibold))
                        Text("Verified — you can sign in with this number")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.coral)
                }
                TextField("New phone number", text: $phoneInput)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                Button {
                    Task { await sendPhoneCode() }
                } label: {
                    Text(phoneBusy ? "Sending…" : "Send verification code")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                .disabled(phoneBusy || !phoneChanged)
                if accountEmail != nil {
                    Button(role: .destructive) {
                        Task { await removePhone() }
                    } label: {
                        Text(phoneBusy ? "Removing…" : "Remove phone number")
                            .font(Theme.body(14, weight: .semibold))
                    }
                    .disabled(phoneBusy)
                } else {
                    Text("Add an email sign-in before removing your phone, so you aren't locked out.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("Add a phone number to sign in with SMS.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("+1 555 123 4567", text: $phoneInput)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                Button {
                    Task { await sendPhoneCode() }
                } label: {
                    Text(phoneBusy ? "Sending…" : "Send verification code")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                .disabled(
                    phoneBusy
                        || phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if let phoneError {
                Text(phoneError)
                    .font(Theme.body(12))
                    .foregroundStyle(.red)
            }
            if let phoneSuccess {
                Text(phoneSuccess)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.coral)
            }
        } header: {
            Text("Phone number")
        } footer: {
            Text("Used to sign in and to match appreciations sent to your number.")
        }
        .listRowBackground(Theme.surface)
    }

    private func normalizeNonprofitWebsite() {
        let trimmed = (nonprofitWebsite ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nonprofitWebsite = nil
            return
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            nonprofitWebsite = trimmed
        } else {
            nonprofitWebsite = "https://\(trimmed)"
        }
    }

    private func loadPhoneState() async {
        accountEmail = await auth.currentAccountEmail()
        let phone = await auth.currentConfirmedPhone()
        verifiedPhone = phone
        if !phoneCodeSent {
            phoneInput = phone ?? ""
        }
    }

    private func sendPhoneCode() async {
        phoneError = nil
        phoneSuccess = nil
        guard let normalized = AuthService.normalizedPhone(phoneInput) else {
            phoneError = "Enter a valid phone number (include country code, e.g. +1 415 555 1234)."
            return
        }
        phoneBusy = true
        phoneInput = normalized
        let ok = await auth.sendPhoneChangeCode(to: normalized)
        phoneBusy = false
        if ok {
            phoneCodeSent = true
            phoneCode = ""
            phoneSuccess = "We sent a 6-digit code to \(normalized)."
        } else {
            phoneError = auth.errorMessage
        }
    }

    private func verifyPhone() async {
        phoneError = nil
        phoneSuccess = nil
        phoneBusy = true
        let ok = await auth.verifyPhoneChange(phone: phoneInput, code: phoneCode)
        phoneBusy = false
        if ok {
            verifiedPhone = phoneInput
            phoneCodeSent = false
            phoneCode = ""
            phoneSuccess = "Phone number verified and saved."
        } else {
            phoneError = auth.errorMessage ?? "That code was incorrect or expired."
        }
    }

    private func cancelPhoneChange() {
        phoneCodeSent = false
        phoneCode = ""
        phoneError = nil
        phoneSuccess = nil
        phoneInput = verifiedPhone ?? ""
    }

    private func removePhone() async {
        phoneError = nil
        phoneSuccess = nil
        phoneBusy = true
        let ok = await auth.removePhone()
        phoneBusy = false
        if ok {
            verifiedPhone = nil
            phoneInput = ""
            phoneCodeSent = false
            phoneCode = ""
            phoneSuccess = "Phone number removed."
        } else {
            phoneError = auth.errorMessage ?? "Couldn't remove phone number."
        }
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
                      let jpegData = ImageProcessing.jpegForAvatar(image) else {
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
                if nonprofitName != nil {
                    normalizeNonprofitWebsite()
                    let site = (nonprofitWebsite ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if site.isEmpty {
                        errorMessage = "Add the nonprofit's website."
                        saving = false
                        return
                    }
                }
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
