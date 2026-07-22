import SwiftUI
import AppIntents

/// One-time post-login tip. App Shortcuts don’t need a system “enable” toggle —
/// they register when the app launches — but most people won’t discover phrases
/// unless we show them.
struct SiriIntroView: View {
    var onFinished: () -> Void

    @State private var tipVisible = true

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ActionGlyph(systemImage: "waveform", size: 88)

                VStack(spacing: 10) {
                    Text("Thank someone with Siri")
                        .font(Theme.display(28, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("No setup needed — just say something like “Thank Maria on OpenThanks” or “Create an OpenThanks post.”")
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                SiriTipView(intent: ThankSomeoneIntent(), isVisible: $tipVisible)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                Button("Got it", action: onFinished)
                    .buttonStyle(CTAButtonStyle())

                Button {
                    onFinished()
                } label: {
                    Text("Not now")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .syncAppAppearance()
        .onAppear {
            OpenThanksShortcuts.updateAppShortcutParameters()
        }
    }
}
