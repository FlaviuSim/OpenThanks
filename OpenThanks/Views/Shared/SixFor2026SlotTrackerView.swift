import SwiftUI

/// Subtle two-line Six for '26 breakdown for Stats — who already counts, who’s pending.
struct SixFor2026SlotTrackerView: View {
    var counted: [GratitudeService.SixFor2026SlotEntry]
    var pending: [GratitudeService.SixFor2026SlotEntry]
    var total: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(countedLine)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            if let pendingLine {
                Text(pendingLine)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([countedLine, pendingLine].compactMap { $0 }.joined(separator: ". "))
    }

    private var countedLine: String {
        if counted.isEmpty {
            return "Counted: none yet"
        }
        let names = counted.map(\.recipientLabel)
        return "Counted: \(joinedNames(names))"
    }

    private var pendingLine: String? {
        if pending.isEmpty {
            let open = max(0, total - counted.count)
            return open > 0 ? "\(open) open \(open == 1 ? "slot" : "slots")" : nil
        }
        let names = pending.map(\.recipientLabel)
        let open = max(0, total - counted.count - pending.count)
        var line = "Pending: \(joinedNames(names))"
        if open > 0 {
            line += " · \(open) open"
        }
        return line
    }

    /// Keeps one line: first names, then “+N more” if needed.
    private func joinedNames(_ names: [String]) -> String {
        let trimmed = names.map { firstName(of: $0) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "—" }
        if trimmed.count <= 3 {
            return trimmed.joined(separator: ", ")
        }
        let head = trimmed.prefix(2).joined(separator: ", ")
        return "\(head) +\(trimmed.count - 2) more"
    }

    private func firstName(of label: String) -> String {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.split(whereSeparator: { $0.isWhitespace }).first else { return t }
        return String(first)
    }
}
