import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @Environment(AuthService.self) private var auth
    @State private var showEmailSheet = false
    @State private var showPhoneSheet = false

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
                // Apple first: required by App Review when other social logins exist.
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await auth.signInWithApple(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                authButton(icon: "g.circle.fill", label: "Continue with Google") {
                    Task { await auth.signInWithGoogle() }
                }
                authButton(icon: "envelope.fill", label: "Continue with Email") {
                    showEmailSheet = true
                }
                authButton(icon: "phone.fill", label: "Continue with Phone") {
                    showPhoneSheet = true
                }
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
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17))
                Text(label).font(Theme.body(16, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        }
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(codeSent ? "Enter the 6-digit code" :
                        (mode == .email ? "What's your email?" : "What's your number?"))
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if !codeSent {
                    TextField(mode == .email ? "you@example.com" : "+1 555 123 4567",
                              text: $destination)
                        .keyboardType(mode == .email ? .emailAddress : .phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .font(Theme.display(28, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.textPrimary)
                }

                if let error = auth.errorMessage {
                    Text(error).font(Theme.body(13)).foregroundStyle(.red)
                }

                Button(codeSent ? "Verify" : "Send code") {
                    Task {
                        busy = true
                        defer { busy = false }
                        if codeSent {
                            if mode == .email {
                                await auth.verifyEmailCode(email: destination, code: code)
                            } else {
                                await auth.verifyPhoneCode(phone: normalizedPhone, code: code)
                            }
                            if case .signedIn = auth.state { dismiss() }
                        } else {
                            let ok = mode == .email
                                ? await auth.sendEmailCode(to: destination)
                                : await auth.sendPhoneCode(to: normalizedPhone)
                            if ok { codeSent = true }
                        }
                    }
                }
                .buttonStyle(CTAButtonStyle())
                .disabled(busy || (codeSent ? code.count < 6 : destination.isEmpty))

                Spacer()
            }
            .padding(24)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var normalizedPhone: String {
        let digits = destination.filter { $0.isNumber || $0 == "+" }
        return digits.hasPrefix("+") ? digits : "+1\(digits)"
    }
}
