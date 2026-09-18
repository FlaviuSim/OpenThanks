import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    private struct Slide {
        let headline: [String]           // lines; last line rendered in coral
        let points: [(icon: String, title: String, body: String)]
    }

    private let slides: [Slide] = [
        .init(headline: ["Gratitude", "changes", "everything"],
              points: [
                ("sparkles", "Inspire",
                 "Your thanks can brighten someone's day—and inspire others to do the same."),
                ("star.fill", "Stay Connected",
                 "Gratitude strengthens your relationships and keeps you close."),
                ("heart.fill", "Invest in Relationships",
                 "The people who matter today are the ones you'll need tomorrow."),
              ]),
        .init(headline: ["Say it", "while it", "matters"],
              points: [
                ("paperplane.fill", "Send in seconds",
                 "A name and a few honest words. That's the whole product."),
                ("lock.fill", "Accept before anything is public",
                 "Recipients must accept before a thank-you can appear on OpenThanks — this isn't marketing spam."),
              ]),
    ]

    private var progress: CGFloat {
        CGFloat(page + 1) / CGFloat(slides.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.surfaceRaised)
                        Capsule()
                            .fill(Theme.heartGradient)
                            .frame(width: max(18, geo.size.width * progress))
                            .animation(Motion.breathe, value: page)
                    }
                }
                .frame(height: 6)
                .frame(maxWidth: 120)

                Text("\(page + 1) of \(slides.count)")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())

                Spacer()
                Button("Skip") {
                    Analytics.capture("prelogin_onboarding_skipped")
                    onFinish()
                }
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)

            // Avoid `.tabViewStyle(.page)` — on iPad it can intercept taps meant for
            // the Continue button below (App Review: unresponsive Continue).
            slideView(slides[page], index: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(page)
                .transition(.opacity)
                .animation(Motion.breathe, value: page)
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            if value.translation.width < -60, page < slides.count - 1 {
                                withAnimation(Motion.breathe) { page += 1 }
                            } else if value.translation.width > 60, page > 0 {
                                withAnimation(Motion.breathe) { page -= 1 }
                            }
                        }
                )

            Button(page == slides.count - 1 ? "Get Started" : "Continue") {
                WarmHaptics.selection()
                if page == slides.count - 1 {
                    Analytics.capture("prelogin_onboarding_completed")
                    onFinish()
                } else {
                    withAnimation(Motion.breathe) { page += 1 }
                }
            }
            .buttonStyle(CTAButtonStyle())
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            .accessibilityLabel(page == slides.count - 1 ? "Get Started" : "Continue")
            .sensoryFeedback(.selection, trigger: page)

            HStack(spacing: 6) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.coral : Theme.textTertiary.opacity(0.45))
                        .frame(width: i == page ? 18 : 6, height: 6)
                        .animation(Motion.breathe, value: page)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .readableWidth()
    }

    private func slideView(_ slide: Slide, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(slide.headline.indices, id: \.self) { i in
                    Text(slide.headline[i])
                        .font(Theme.display(40, weight: .semibold))
                        .foregroundStyle(i == slide.headline.count - 1
                                         ? AnyShapeStyle(Theme.heartGradient)
                                         : AnyShapeStyle(Theme.textPrimary))
                }
            }
            .padding(.top, 24)
            .softNoteReveal(delay: 0.02)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(slide.points.enumerated()), id: \.element.title) { pointIndex, point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.coralLight)
                            .frame(width: 40, height: 40)
                            .background(Theme.surfaceRaised, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title)
                                .font(Theme.body(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(point.body)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .softNoteReveal(delay: 0.08 + Double(pointIndex) * 0.06)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .id(index)
    }
}
