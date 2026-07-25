import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @Environment(AuthService.self) private var auth
    @State private var showEmailSheet = false
    @State private var showPhoneSheet = false
    @State private var oauthBusy = false

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
                .padding(.bottom, 36)

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(oauthBusy)

                authButton(
                    iconView: AnyView(GoogleGlyph()),
                    label: oauthBusy ? "Opening Google…" : "Continue with Google"
                ) {
                    Task { await signInWithGoogle() }
                }
                .disabled(oauthBusy)
                .opacity(oauthBusy ? 0.7 : 1)

                authButton(icon: "envelope.fill", label: "Continue with Email") {
                    showEmailSheet = true
                }
                .disabled(oauthBusy)

                authButton(icon: "phone.fill", label: "Continue with Phone") {
                    showPhoneSheet = true
                }
                .disabled(oauthBusy)
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

    private func signInWithGoogle() async {
        guard !oauthBusy else { return }
        oauthBusy = true
        defer { oauthBusy = false }
        _ = await auth.signInWithGoogle()
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
            Task {
                oauthBusy = true
                defer { oauthBusy = false }
                _ = await auth.signInWithApple(
                    idToken: idToken,
                    fullName: appleFullName
                )
            }
        }
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
            let ok = mode == .email
                ? await auth.sendEmailCode(to: destination)
                : await auth.sendPhoneCode(to: normalizedPhone)
            if ok {
                codeSent = true
            } else {
                destinationFocused = true
            }
        }
    }

    private var normalizedPhone: String {
        AuthService.normalizedPhone(destination) ?? destination
    }
}
