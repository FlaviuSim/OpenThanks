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

/// Reports how much of this view the keyboard currently covers.
/// A parent that already shrunk above the keyboard reports 0.
struct KeyboardCoverReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = onChange
    }

    final class Probe: UIView {
        var onChange: (CGFloat) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        private var keyboardFrame: CGRect?
        private var lastReported: CGFloat = -1

        override init(frame: CGRect) {
            super.init(frame: frame)
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.keyboardFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                    self?.report()
                },
                center.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrame = nil
                    self?.report(forced: 0)
                },
            ]
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        private func report(forced: CGFloat? = nil) {
            let overlap: CGFloat
            if let forced {
                overlap = forced
            } else if let keyboardFrame, let window {
                let keyboard = window.convert(keyboardFrame, from: nil)
                let mine = convert(bounds, to: window)
                overlap = max(0, mine.maxY - keyboard.minY)
            } else {
                overlap = 0
            }
            guard abs(overlap - lastReported) > 0.5 else { return }
            lastReported = overlap
            onChange(overlap)
        }
    }
}
