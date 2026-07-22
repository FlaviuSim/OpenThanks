import SwiftUI
import UIKit

/// Quiet motion language for OpenThanks — handwritten note, not a game or a feed.
enum Motion {
    /// Soft settle — opening a card.
    static let note: Animation = .spring(response: 0.62, dampingFraction: 0.86)
    /// Slightly quicker for progress / chrome.
    static let breathe: Animation = .spring(response: 0.48, dampingFraction: 0.88)
    /// Long fade for ripples and dust.
    static let linger: Animation = .easeOut(duration: 1.15)
}

enum WarmHaptics {
    /// Receiving or opening a thank-you — soft, not celebratory.
    static func received() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }

    /// Sharing / sending — a gentle confirmation.
    static func shared() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Soft card expansion (reading a note)

struct SoftNoteRevealModifier: ViewModifier {
    @State private var revealed = false
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 0.97, anchor: .top)
            .offset(y: revealed ? 0 : 10)
            .onAppear {
                withAnimation(Motion.note.delay(delay)) {
                    revealed = true
                }
            }
    }
}

extension View {
    /// Fades and gently expands like unfolding a handwritten note.
    func softNoteReveal(delay: Double = 0) -> some View {
        modifier(SoftNoteRevealModifier(delay: delay))
    }
}

// MARK: - Gratitude ripple (shared / sent)

/// Concentric coral rings — a pulse of warmth, not confetti.
struct GratitudeRipple: View {
    var trigger: Bool
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Theme.coral.opacity(trigger ? 0 : 0.28 - Double(i) * 0.07), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(trigger ? 1.55 + CGFloat(i) * 0.35 : 0.55)
                    .animation(
                        Motion.linger.delay(Double(i) * 0.09),
                        value: trigger
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A few slow-drifting motes — tasteful, sparse (not party confetti).
struct SoftAppreciationDust: View {
    var active: Bool

    private let motes: [(x: CGFloat, delay: Double, size: CGFloat)] = [
        (-36, 0.00, 5),
        (28, 0.08, 4),
        (-12, 0.14, 3),
        (42, 0.05, 3.5),
        (8, 0.18, 4),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(motes.enumerated()), id: \.offset) { _, mote in
                Circle()
                    .fill(Theme.coralPale.opacity(active ? 0 : 0.55))
                    .frame(width: mote.size, height: mote.size)
                    .offset(
                        x: mote.x,
                        y: active ? -56 : 8
                    )
                    .blur(radius: 0.3)
                    .animation(
                        .easeOut(duration: 1.4).delay(mote.delay),
                        value: active
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Heart + ripple + sparse dust for post-send / share moments.
struct AppreciationMoment: View {
    var size: CGFloat = 88
    @State private var lit = false

    var body: some View {
        ZStack {
            GratitudeRipple(trigger: lit, size: size * 1.05)
            SoftAppreciationDust(active: lit)
            HeartMark(size: size)
                .scaleEffect(lit ? 1 : 0.72)
                .opacity(lit ? 1 : 0.55)
                .animation(Motion.note, value: lit)
        }
        .onAppear {
            WarmHaptics.shared()
            withAnimation {
                lit = true
            }
        }
    }
}
