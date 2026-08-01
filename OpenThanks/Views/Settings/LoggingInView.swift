import SwiftUI
import Supabase

/// Sign-in methods for the current account: emails, Google, phone.
struct LoggingInView: View {
    @Environment(AuthService.self) private var auth

    @State private var identities: [UserIdentity] = []
    @State private var verifiedPhone: String?
    @State private var primaryEmail: String?
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Email add / verify
    @State private var emailInput = ""
    @State private var emailCode = ""
    @State private var emailCodeSent = false

    // Phone add / change / verify
    @State private var phoneInput = ""
    @State private var phoneCode = ""
    @State private var phoneCodeSent = false

    @State private var identityToUnlink: UserIdentity?

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
            Section {
                Text("These are the ways you can sign in to this OpenThanks account. Link more so a work email, personal email, or Google all open the same profile.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            }

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
        .confirmationDialog(
            "Disconnect this sign-in method?",
            isPresented: Binding(
                get: { identityToUnlink != nil },
                set: { if !$0 { identityToUnlink = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                if let identityToUnlink {
                    Task { await unlink(identityToUnlink) }
                }
            }
            Button("Cancel", role: .cancel) { identityToUnlink = nil }
        } message: {
            if let identity = identityToUnlink {
                Text("You won’t be able to sign in with \(AuthService.identityLabel(for: identity)) until you link it again.")
            }
        }
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
                    canDisconnect: true
                ) {
                    identityToUnlink = identity
                }
            }

            if emailCodeSent {
                Text(emailInput)
                    .font(Theme.body(15, weight: .semibold))
                OneTimeCodeField(text: $emailCode, isFocused: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .onChange(of: emailCode) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { emailCode = digits }
                        guard digits.count == 6, !busy else { return }
                        Task { await verifyEmail() }
                    }
                if busy {
                    ProgressView().tint(Theme.coral)
                } else {
                    Button("Verify email code") { Task { await verifyEmail() } }
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .disabled(emailCode.count < 6)
                    Button("Cancel") { cancelEmailChange() }
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                TextField("Add another email", text: $emailInput)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                Button {
                    Task { await sendEmailCode() }
                } label: {
                    Text(busy ? "Sending…" : "Send verification code")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                .disabled(
                    busy
                        || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        } header: {
            Text("Email")
        } footer: {
            Text("We’ll email a code to confirm. After it’s verified, you can sign in with that address on this account.")
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
                    identityToUnlink = identity
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
        } footer: {
            Text("Used to sign in and to match appreciations sent to your number.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Rows

    private func identityRow(
        title: String,
        subtitle: String,
        systemImage: String,
        canDisconnect: Bool,
        onDisconnect: (() -> Void)? = nil
    ) -> some View {
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
            if canDisconnect, let onDisconnect {
                Button("Disconnect", action: onDisconnect)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.9))
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.coral)
            }
        }
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
    }

    private func clearBanners() {
        errorMessage = nil
        successMessage = nil
    }

    private func sendEmailCode() async {
        clearBanners()
        busy = true
        let ok = await auth.sendEmailLinkCode(to: emailInput)
        busy = false
        if ok {
            emailInput = AuthService.normalizedEmail(emailInput)
            emailCodeSent = true
            emailCode = ""
            successMessage = "We sent a code to \(emailInput)."
        } else {
            errorMessage = auth.errorMessage
        }
    }

    private func verifyEmail() async {
        clearBanners()
        busy = true
        let ok = await auth.verifyEmailLinkCode(email: emailInput, code: emailCode)
        busy = false
        if ok {
            emailCodeSent = false
            emailCode = ""
            emailInput = ""
            successMessage = "Email verified. You can sign in with it on this account."
            await reload()
        } else {
            errorMessage = auth.errorMessage ?? "That code was incorrect or expired."
        }
    }

    private func cancelEmailChange() {
        emailCodeSent = false
        emailCode = ""
        clearBanners()
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
        identityToUnlink = nil
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
