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

        let screen = UIScreen.main.bounds
        // Off-screen / dismissed keyboards report a frame below the display.
        let overlap = frame.minY >= screen.maxY - 0.5
            ? 0
            : max(0, screen.maxY - frame.minY)

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
            .doubleValue ?? 0.25
        setOverlap(overlap, duration: duration)
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
