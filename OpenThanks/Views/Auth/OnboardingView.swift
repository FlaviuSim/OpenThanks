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
                ("envelope.fill", "No account needed to receive",
                 "Recipients get your appreciation by email or text and claim it when ready."),
              ]),
        .init(headline: ["Built for", "the person", "receiving it"],
              points: [
                ("person.fill", "Their moment, not your feed",
                 "Every appreciation centers the recipient."),
                ("lock.fill", "Public or private",
                 "You choose what the world sees. They choose what they keep."),
              ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(page + 1) of \(slides.count)")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.surfaceRaised, in: Capsule())
                Spacer()
                Button("Skip") { onFinish() }
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    slideView(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button(page == slides.count - 1 ? "Get Started" : "Continue") {
                if page == slides.count - 1 { onFinish() }
                else { withAnimation { page += 1 } }
            }
            .buttonStyle(CTAButtonStyle())
            .padding(.horizontal, 24)

            HStack(spacing: 6) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.coral : Theme.textTertiary.opacity(0.5))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(Theme.background)
    }

    private func slideView(_ slide: Slide) -> some View {
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

            VStack(alignment: .leading, spacing: 22) {
                ForEach(slide.points, id: \.title) { point in
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
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}
