import SwiftUI

/// Warm prompt at the top of My Feed for someone who has not sent a thank-you yet.
///
/// Lives in the feed column, under the My Feed / World Feed picker. The
/// Thanksgiving-week icon banner stays in the top chrome, and the turkey decal
/// stays in the picker's trailing slot — this card does not use either.
struct FirstThanksCard: View {
    var suggestions: FirstThanksSuggestionSet
    var onSelect: (FirstThanksSuggestion) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                heartMark
                VStack(alignment: .leading, spacing: 4) {
                    Text("A note worth sending")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    Text("Who helped you this week?")
                        .font(Theme.display(22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text("Think of someone who made things a little easier. A few honest words are a real thank-you.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            suggestionsBlock

            Button(action: onDismiss) {
                Text("Not now")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Hides this for now. It can come back on your next visit.")
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var suggestionsBlock: some View {
        switch suggestions.kind {
        case .people:
            VStack(spacing: 8) {
                ForEach(suggestions.items) { item in
                    suggestionButton(item)
                }
            }
        case .relationships:
            WrappingSuggestionChips {
                ForEach(suggestions.items) { item in
                    suggestionButton(item)
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionButton(_ item: FirstThanksSuggestion) -> some View {
        switch item {
        case .person(_, let name, let source):
            Button {
                onSelect(item)
            } label: {
                HStack(spacing: 10) {
                    Text(initials(for: name))
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 36, height: 36)
                        .background(Theme.brandTint, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(source.subtitle)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("Thank")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.ctaGradient, in: Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thank \(name)")
            .accessibilityHint(source.subtitle)
        case .relationship(let relationship):
            Button {
                onSelect(item)
            } label: {
                Text(relationship.title)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.brandTint, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thank a \(relationship.title.lowercased())")
        }
    }

    private var heartMark: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.onPrimary)
            .frame(width: 36, height: 36)
            .background(Theme.heartGradient, in: Circle())
            .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.primary.opacity(0.16),
                                Theme.surface.opacity(0.02),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.28), lineWidth: 1)
            )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = parts.compactMap { $0.first }
        let text = String(letters).uppercased()
        return text.isEmpty ? "•" : text
    }
}

/// Chips wrap onto the next line on a narrow phone and stay in one row when there is room.
private struct WrappingSuggestionChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(for: subviews, maxWidth: width)
        let height = rows.reduce(CGFloat(0)) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.view.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        var view: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [Item]
        var height: CGFloat
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current: [Item] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let nextWidth = current.isEmpty ? size.width : rowWidth + spacing + size.width
            if !current.isEmpty, nextWidth > maxWidth {
                rows.append(Row(items: current, height: rowHeight))
                current = []
                rowWidth = 0
                rowHeight = 0
            }
            current.append(Item(view: view, size: size))
            rowWidth = current.count == 1 ? size.width : rowWidth + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
        if !current.isEmpty {
            rows.append(Row(items: current, height: rowHeight))
        }
        return rows
    }
}
