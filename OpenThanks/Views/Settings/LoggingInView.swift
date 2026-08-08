import SwiftUI
@_spi(Experimental) import Supabase

/// Sign-in methods for the current account: email, Google, phone, passkeys.
struct LoggingInView: View {
    @Environment(AuthService.self) private var auth

    @State private var identities: [UserIdentity] = []
    @State private var passkeys: [PasskeyListItem] = []
    @State private var verifiedPhone: String?
    @State private var primaryEmail: String?
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Phone add / change / verify
    @State private var phoneInput = ""
    @State private var phoneCode = ""
    @State private var phoneCodeSent = false

    private var phoneChanged: Bool {
        AuthService.normalizedPhone(phoneInput) != verifiedPhone
    }

    private var hasGoogleIdentity: Bool {
        identities.contains { $0.provider.lowercased() == "google" }
    }

    private var emailIdentities: [UserIdentity] {
        identities.filter { $0.provider.lowercased() == "email" }
    }

    private var socialIdentities: [UserIdentity] {
        identities.filter {
            let p = $0.provider.lowercased()
            return p != "email" && p != "phone"
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(Theme.body(13))
                        .foregroundStyle(.red)
                }
                .listRowBackground(Theme.surface)
            }
            if let successMessage {
                Section {
                    Text(successMessage)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.coral)
                }
                .listRowBackground(Theme.surface)
            }

            emailsSection
            googleSection
            phoneSection
            passkeysSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
        .navigationTitle("Logging In")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading {
                ProgressView()
                    .tint(Theme.coral)
            }
        }
        .disabled(busy)
        .task { await reload() }
        .refreshable { await reload() }
        .syncAppAppearance()
    }

    // MARK: - Emails

    private var emailsSection: some View {
        Section {
            if emailIdentities.isEmpty, let primaryEmail, !primaryEmail.isEmpty {
                identityRow(
                    title: primaryEmail,
                    subtitle: "Account email",
                    systemImage: "envelope.fill",
                    canDisconnect: false
                )
            }

            ForEach(emailIdentities, id: \.identityId) { identity in
                identityRow(
                    title: AuthService.identityLabel(for: identity),
                    subtitle: "Email · verified",
                    systemImage: "envelope.fill",
                    canDisconnect: false
                )
            }
        } header: {
            Text("Email")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Google

    private var googleSection: some View {
        Section {
            ForEach(socialIdentities, id: \.identityId) { identity in
                identityRow(
                    title: AuthService.identityLabel(for: identity),
                    subtitle: "\(identity.provider.capitalized) · connected",
                    systemImage: identity.provider.lowercased() == "google"
                        ? "g.circle.fill" : "person.crop.circle.fill",
                    canDisconnect: true
                ) {
                    Task { await unlink(identity) }
                }
            }

            if !hasGoogleIdentity {
                Button {
                    Task { await linkGoogle() }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .foregroundStyle(Theme.coral)
                        Text(busy ? "Connecting…" : "Connect Google")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                        Spacer()
                    }
                }
                .disabled(busy)
            }
        } header: {
            Text("Google & social")
        } footer: {
            Text("Sign in with Google uses the same OpenThanks account. This is separate from connecting Google Calendar for evening nudges.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Phone

    @ViewBuilder
    private var phoneSection: some View {
        Section {
            if phoneCodeSent {
                Text(phoneInput)
                    .font(Theme.body(15, weight: .semibold))
                OneTimeCodeField(text: $phoneCode, isFocused: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .onChange(of: phoneCode) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { phoneCode = digits }
                        guard digits.count == 6, !busy else { return }
                        Task { await verifyPhone() }
                    }
                if busy {
                    ProgressView().tint(Theme.coral)
                } else {
                    Button("Verify phone code") { Task { await verifyPhone() } }
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
                    Text(busy ? "Sending…" : "Send verification code")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                .disabled(busy || !phoneChanged)
                Button(role: .destructive) {
                    Task { await removePhone() }
                } label: {
                    Text(busy ? "Removing…" : "Disconnect phone")
                        .font(Theme.body(14, weight: .semibold))
                }
                .disabled(busy)
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
                    Text(busy ? "Sending…" : "Send verification code")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                .disabled(
                    busy
                        || phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        } header: {
            Text("Phone")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Passkeys

    private var passkeysSection: some View {
        Section {
            if passkeys.isEmpty {
                Text("No passkeys yet. Add one to sign in with Face ID or Touch ID on this and other devices.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(passkeys) { passkey in
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundStyle(Theme.coral)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(passkey.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                                ?? "Passkey")
                                .font(Theme.body(15, weight: .semibold))
                            Text(passkeySubtitle(passkey))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await removePasskey(passkey) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .disabled(busy)
                    }
                }
            }

            Button {
                Task { await addPasskey() }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.coral)
                    Text(busy ? "Waiting…" : "Add a passkey")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                    Spacer()
                }
            }
            .disabled(busy)
        } header: {
            Text("Passkeys")
        } footer: {
            Text("Passkeys sync via iCloud Keychain or your password manager so you can sign in on web and iPhone without a code.")
        }
        .listRowBackground(Theme.surface)
    }

    private func passkeySubtitle(_ passkey: PasskeyListItem) -> String {
        let created = passkey.createdAt.formatted(date: .abbreviated, time: .omitted)
        if let last = passkey.lastUsedAt {
            let lastText = last.formatted(date: .abbreviated, time: .omitted)
            return "Added \(created) · Last used \(lastText)"
        }
        return "Added \(created)"
    }

    // MARK: - Rows

    private func identityRow(
        title: String,
        subtitle: String,
        systemImage: String,
        canDisconnect: Bool,
        onDisconnect: (() -> Void)? = nil
    ) -> some View {
        IdentityRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            canDisconnect: canDisconnect,
            onDisconnect: onDisconnect
        )
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        defer { loading = false }
        identities = await auth.fetchLinkedIdentities()
        primaryEmail = await auth.currentAccountEmail()
        verifiedPhone = await auth.currentConfirmedPhone()
        if !phoneCodeSent {
            phoneInput = verifiedPhone ?? ""
        }
        passkeys = await auth.listPasskeys()
    }

    private func addPasskey() async {
        clearBanners()
        busy = true
        let ok = await auth.registerPasskey()
        busy = false
        if ok {
            successMessage = "Passkey added. You can use Face ID or Touch ID to sign in."
            await reload()
        } else if let message = auth.errorMessage {
            errorMessage = message
        }
    }

    private func removePasskey(_ passkey: PasskeyListItem) async {
        clearBanners()
        busy = true
        let ok = await auth.deletePasskey(id: passkey.id)
        busy = false
        if ok {
            passkeys.removeAll { $0.id == passkey.id }
            successMessage = "Passkey removed."
        } else {
            errorMessage = auth.errorMessage ?? "Couldn't remove passkey."
        }
    }

    private func clearBanners() {
        errorMessage = nil
        successMessage = nil
    }

    private func linkGoogle() async {
        clearBanners()
        busy = true
        let ok = await auth.linkGoogleIdentity()
        busy = false
        if ok {
            successMessage = "Google connected. You can sign in with that Google account."
            await reload()
        } else if let message = auth.errorMessage {
            errorMessage = message
        }
    }

    private func unlink(_ identity: UserIdentity) async {
        clearBanners()
        busy = true
        let ok = await auth.unlinkIdentity(identity)
        busy = false
        if ok {
            successMessage = "Disconnected \(AuthService.identityLabel(for: identity))."
            await reload()
        } else {
            errorMessage = auth.errorMessage
        }
    }

    private func sendPhoneCode() async {
        clearBanners()
        guard let normalized = AuthService.normalizedPhone(phoneInput) else {
            errorMessage = "Enter a valid phone number (include country code, e.g. +1 415 555 1234)."
            return
        }
        busy = true
        phoneInput = normalized
        let ok = await auth.sendPhoneChangeCode(to: normalized)
        busy = false
        if ok {
            phoneCodeSent = true
            phoneCode = ""
            successMessage = "We sent a 6-digit code to \(normalized)."
        } else {
            errorMessage = auth.errorMessage
        }
    }

    private func verifyPhone() async {
        clearBanners()
        busy = true
        let ok = await auth.verifyPhoneChange(phone: phoneInput, code: phoneCode)
        busy = false
        if ok {
            verifiedPhone = phoneInput
            phoneCodeSent = false
            phoneCode = ""
            successMessage = "Phone number verified."
            await reload()
        } else {
            errorMessage = auth.errorMessage ?? "That code was incorrect or expired."
        }
    }

    private func cancelPhoneChange() {
        phoneCodeSent = false
        phoneCode = ""
        clearBanners()
        phoneInput = verifiedPhone ?? ""
    }

    private func removePhone() async {
        clearBanners()
        busy = true
        let ok = await auth.removePhone()
        busy = false
        if ok {
            verifiedPhone = nil
            phoneInput = ""
            phoneCodeSent = false
            phoneCode = ""
            successMessage = "Phone disconnected."
            await reload()
        } else {
            errorMessage = auth.errorMessage ?? "Couldn't remove phone number."
        }
    }
}

/// Keeps the confirmation dialog anchored to the Disconnect control (avoids popover at the top of the screen).
private struct IdentityRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let canDisconnect: Bool
    let onDisconnect: (() -> Void)?

    @State private var confirmDisconnect = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15, weight: .semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            if canDisconnect, onDisconnect != nil {
                Button("Disconnect") { confirmDisconnect = true }
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.9))
                    .confirmationDialog(
                        "Disconnect this sign-in method?",
                        isPresented: $confirmDisconnect,
                        titleVisibility: .visible
                    ) {
                        Button("Disconnect", role: .destructive) {
                            onDisconnect?()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("You won’t be able to sign in with \(title) until you link it again.")
                    }
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.coral)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
