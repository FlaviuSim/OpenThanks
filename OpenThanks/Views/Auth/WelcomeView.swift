import AuthenticationServices
import SwiftUI
import UIKit

struct WelcomeView: View {
    private enum OAuthBusy: Equatable {
        case google, linkedin, apple, passkey
    }

    @Environment(AuthService.self) private var auth
    @State private var showEmailSheet = false
    @State private var showPhoneSheet = false
    @State private var oauthBusy: OAuthBusy?
    @State private var ageConfirmed = false
    @State private var showAgeHint = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.heartGradient)
                    .font(.system(size: 24))
                Text("OpenThanks")
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.bottom, 28)

            Text("Welcome back")
                .font(Theme.display(32, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Sign in to continue sharing appreciation.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
                .padding(.bottom, 28)

            AgeConfirmationToggle(
                isConfirmed: $ageConfirmed,
                showHint: $showAgeHint
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            VStack(spacing: 12) {
                ZStack {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(!ageConfirmed || oauthBusy != nil)
                    .opacity(ageConfirmed ? 1 : 0.45)

                    if !ageConfirmed {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { nudgeAgeConfirmation() }
                    }
                }
                .frame(height: 52)

                authButton(
                    iconView: AnyView(GoogleGlyph()),
                    label: oauthBusy == .google ? "Opening Google…" : "Continue with Google"
                ) {
                    guardRequireAge {
                        Task { await signInWithOAuth(.google) }
                    }
                }
                .disabled(oauthBusy != nil)
                .opacity(authControlOpacity)

                authButton(
                    iconView: AnyView(LinkedInGlyph()),
                    label: oauthBusy == .linkedin ? "Opening LinkedIn…" : "Continue with LinkedIn"
                ) {
                    guardRequireAge {
                        Task { await signInWithOAuth(.linkedin) }
                    }
                }
                .disabled(oauthBusy != nil)
                .opacity(authControlOpacity)

                authButton(
                    icon: "person.badge.key.fill",
                    label: oauthBusy == .passkey ? "Waiting for passkey…" : "Continue with Passkey"
                ) {
                    guardRequireAge {
                        Task { await signInWithPasskey() }
                    }
                }
                .disabled(oauthBusy != nil)
                .opacity(authControlOpacity)

                authButton(icon: "envelope.fill", label: "Continue with Email") {
                    guardRequireAge { showEmailSheet = true }
                }
                .disabled(oauthBusy != nil)
                .opacity(authControlOpacity)

                authButton(icon: "phone.fill", label: "Continue with Phone") {
                    guardRequireAge { showPhoneSheet = true }
                }
                .disabled(oauthBusy != nil)
                .opacity(authControlOpacity)
            }
            .padding(.horizontal, 24)

            if let error = auth.errorMessage {
                Text(error)
                    .font(Theme.body(13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
            }

            Spacer()

            legalFooter
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showEmailSheet) { OTPSheet(mode: .email) }
        .sheet(isPresented: $showPhoneSheet) { OTPSheet(mode: .phone) }
    }

    private var authControlOpacity: Double {
        if oauthBusy != nil { return 0.7 }
        return ageConfirmed ? 1 : 0.55
    }

    private func guardRequireAge(_ action: () -> Void) {
        guard ageConfirmed else {
            nudgeAgeConfirmation()
            return
        }
        action()
    }

    private func nudgeAgeConfirmation() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showAgeHint = true
        }
        WarmHaptics.selection()
    }

    private var legalFooter: some View {
        Text("By continuing, you agree to our [Terms of Service](https://openthanks.com/terms) and [Privacy Policy](https://openthanks.com/privacy).")
            .font(Theme.body(12))
            .foregroundStyle(Theme.textTertiary)
            .tint(Theme.textSecondary)
            .multilineTextAlignment(.center)
    }

    private func authButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        authButton(
            iconView: AnyView(
                Image(systemName: icon).font(.system(size: 17))
            ),
            label: label,
            action: action
        )
    }

    private func authButton(iconView: AnyView, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                iconView
                Text(label).font(Theme.body(16, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private func signInWithOAuth(_ provider: OAuthBusy) async {
        guard oauthBusy == nil else { return }
        oauthBusy = provider
        defer { oauthBusy = nil }
        switch provider {
        case .google:
            _ = await auth.signInWithGoogle()
        case .linkedin:
            _ = await auth.signInWithLinkedIn()
        case .apple, .passkey:
            break
        }
    }

    private func signInWithPasskey() async {
        guard oauthBusy == nil else { return }
        oauthBusy = .passkey
        defer { oauthBusy = nil }
        _ = await auth.signInWithPasskey()
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled || authError.code == .unknown {
                return
            }
            auth.errorMessage = error.localizedDescription
        case .success(let authorization):
            guard ageConfirmed else {
                nudgeAgeConfirmation()
                return
            }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                auth.errorMessage = "Couldn't complete Sign in with Apple."
                return
            }
            var appleFullName: String?
            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter.localizedString(
                    from: components,
                    style: .default
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !formatted.isEmpty { appleFullName = formatted }
            }
            // Apple only returns email on the first authorization (or after revoke).
            let appleEmail = credential.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                oauthBusy = .apple
                defer { oauthBusy = nil }
                _ = await auth.signInWithApple(
                    idToken: idToken,
                    fullName: appleFullName,
                    email: (appleEmail?.isEmpty == false) ? appleEmail : nil
                )
            }
        }
    }
}

/// Polished 18+ confirmation used on the welcome / OTP auth surfaces.
struct AgeConfirmationToggle: View {
    @Binding var isConfirmed: Bool
    @Binding var showHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isConfirmed.toggle()
                    if isConfirmed { showHint = false }
                }
                WarmHaptics.selection()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isConfirmed ? Theme.coral : Theme.surfaceRaised)
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        isConfirmed ? Theme.coral : Theme.hairline,
                                        lineWidth: 1.5
                                    )
                            )
                        if isConfirmed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("I confirm I am 18 or older")
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text("Required by our Terms of Service")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I confirm I am 18 or older")
            .accessibilityAddTraits(isConfirmed ? [.isSelected] : [])

            Button {
                if let url = URL(string: "https://openthanks.com/terms") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Read Terms of Service")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.coral)
            }
            .buttonStyle(.plain)
            .padding(.leading, 36)

            if showHint {
                Text("Confirm you are 18 or older to continue.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.coral)
                    .padding(.leading, 36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    showHint ? Theme.coral.opacity(0.45) : Theme.hairline,
                    lineWidth: 1
                )
        )
    }
}

/// Minimal multicolor “G” so the Google button reads clearly without an asset.
private struct GoogleGlyph: View {
    var body: some View {
        Text("G")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96),
                        Color(red: 0.22, green: 0.73, blue: 0.33),
                        Color(red: 0.98, green: 0.74, blue: 0.02),
                        Color(red: 0.92, green: 0.26, blue: 0.21),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

private struct LinkedInGlyph: View {
    var body: some View {
        Text("in")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color(red: 0.04, green: 0.40, blue: 0.76), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Two-step one-time-code sheet used for both email and phone sign-in.
struct OTPSheet: View {
    enum Mode { case email, phone }
    let mode: Mode

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @FocusState private var destinationFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(codeSent ? "Enter the 6-digit code" :
                        (mode == .email ? "What's your email?" : "What's your number?"))
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if codeSent {
                    // Plain label — a hidden email TextField steals QuickType taps.
                    Text(destination)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    OneTimeCodeField(text: $code, isFocused: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        // Fresh UITextField when the code step appears so AutoFill
                        // binds to this first responder (not the email field).
                        .id("otp-code-\(mode)-\(destination)")
                } else {
                    TextField(mode == .email ? "you@example.com" : "+1 555 123 4567",
                              text: $destination)
                        .keyboardType(mode == .email ? .emailAddress : .phonePad)
                        .textContentType(mode == .email ? .emailAddress : .telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($destinationFocused)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.textPrimary)
                }

                if let error = auth.errorMessage {
                    Text(error).font(Theme.body(13)).foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 10) {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: 0x2B1209))
                        }
                        Text(submitLabel)
                    }
                }
                .buttonStyle(CTAButtonStyle(isLoading: busy))
                .disabled(busy || !canSubmit)
                .opacity(canSubmit || busy ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.15), value: busy)
                .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: busy)

                Spacer()
            }
            .padding(24)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
            }
            .onAppear { destinationFocused = true }
            .onChange(of: code) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(6))
                if digits != newValue { code = digits }
                guard codeSent, digits.count == 6, !busy else { return }
                Task { await submit() }
            }
        }
        .presentationDetents([.medium])
    }

    private var canSubmit: Bool {
        codeSent ? code.count >= 6 : !trimmedDestination.isEmpty
    }

    private var trimmedDestination: String {
        destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var submitLabel: String {
        if busy {
            return codeSent ? "Verifying…" : "Sending…"
        }
        return codeSent ? "Verify" : "Send code"
    }

    private func submit() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if mode == .email {
            destination = AuthService.normalizedEmail(destination)
        } else {
            destination = trimmedDestination
        }
        if codeSent {
            if mode == .email {
                await auth.verifyEmailCode(email: destination, code: code)
            } else {
                await auth.verifyPhoneCode(phone: normalizedPhone, code: code)
            }
            if case .signedIn = auth.state { dismiss() }
        } else {
            destinationFocused = false
            // Review account: password sign-in, no OTP step (matches web).
            if mode == .email, AuthService.isTestAccountEmail(destination) {
                let ok = await auth.signInTestAccount()
                if ok, case .signedIn = auth.state {
                    dismiss()
                } else {
                    destinationFocused = true
                }
                return
            }
            let ok = mode == .email
                ? await auth.sendEmailCode(to: destination)
                : await auth.sendPhoneCode(to: normalizedPhone)
            if ok {
                // Test account may have signed in inside sendEmailCode — dismiss.
                if case .signedIn = auth.state {
                    dismiss()
                } else {
                    codeSent = true
                }
            } else {
                destinationFocused = true
            }
        }
    }

    private var normalizedPhone: String {
        AuthService.normalizedPhone(destination) ?? destination
    }
}
