import SwiftUI

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
    @FocusState private var destinationFocused: Bool

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
                        .textContentType(mode == .email ? .emailAddress : .telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($destinationFocused)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    OneTimeCodeField(text: $code, isFocused: true)
                        .frame(height: 28)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        // Force a brand-new UITextField when the code step appears so
                        // AutoFill binds to a live .oneTimeCode first responder.
                        .id("otp-code-\(mode)")
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
        codeSent ? code.count >= 6 : !destination.isEmpty
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
        let digits = destination.filter { $0.isNumber || $0 == "+" }
        return digits.hasPrefix("+") ? digits : "+1\(digits)"
    }
}
