import SwiftUI
import UIKit

/// Pads the bottom by the *actual* keyboard overlap while ignoring SwiftUI’s
/// keyboard safe-area. Needed after OAuth / OTP: the system can leave a stale
/// keyboard inset that compresses bottom-pinned chrome mid-screen even when
/// no keyboard is visible.
struct KeyboardBottomPaddingModifier: ViewModifier {
    @State private var keyboardOverlap: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardOverlap)
            .ignoresSafeArea(.keyboard)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            ) { notification in
                updateOverlap(from: notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                setOverlap(0, duration: 0.25)
            }
    }

    private func updateOverlap(from notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        // Prefer the key window so Stage Manager / Split View overlap is correct
        // (UIScreen.main is the full display, not the app’s scene).
        let overlap: CGFloat
        if let window = Self.keyWindow {
            let keyboardInWindow = window.convert(frame, from: nil)
            overlap = keyboardInWindow.minY >= window.bounds.maxY - 0.5
                ? 0
                : max(0, window.bounds.maxY - keyboardInWindow.minY)
        } else {
            let screen = UIScreen.main.bounds
            overlap = frame.minY >= screen.maxY - 0.5
                ? 0
                : max(0, screen.maxY - frame.minY)
        }

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
            .doubleValue ?? 0.25
        setOverlap(overlap, duration: duration)
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return active?.windows.first(where: \.isKeyWindow) ?? active?.windows.first
    }

    private func setOverlap(_ value: CGFloat, duration: Double) {
        guard abs(keyboardOverlap - value) > 0.5 else { return }
        withAnimation(.easeOut(duration: duration)) {
            keyboardOverlap = value
        }
    }
}

extension View {
    /// Full-height layouts that pin a footer: ignore stale keyboard safe-area,
    /// then pad only when a keyboard frame is actually on screen.
    func keyboardBottomPadding() -> some View {
        modifier(KeyboardBottomPaddingModifier())
    }
}
