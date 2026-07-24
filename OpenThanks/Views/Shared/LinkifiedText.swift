import SwiftUI

/// Renders gratitude message text with tappable links: bare URLs and
/// markdown `[label](url)` (same conventions as the web `LinkifiedText`).
struct LinkifiedText: View {
    let text: String
    var font: Font = Theme.body(15)
    var foreground: Color = Theme.textPrimary
    var linkColor: Color = Theme.coral

    var body: some View {
        Text(Self.attributed(text, linkColor: linkColor))
            .font(font)
            .foregroundStyle(foreground)
            .tint(linkColor)
            .textSelection(.enabled)
    }

    static func attributed(_ text: String, linkColor: Color = Theme.coral) -> AttributedString {
        var result = AttributedString()
        guard !text.isEmpty else { return result }

        var remaining = text[...]
        while !remaining.isEmpty {
            if let md = firstMarkdownLink(in: remaining) {
                let before = remaining[..<md.range.lowerBound]
                if !before.isEmpty {
                    result.append(linkifyBareURLs(String(before), linkColor: linkColor))
                }
                var linkText = AttributedString(md.label)
                if let url = normalizedURL(md.url) {
                    linkText.link = url
                    linkText.foregroundColor = linkColor
                    linkText.underlineStyle = .single
                }
                result.append(linkText)
                remaining = remaining[md.range.upperBound...]
            } else {
                result.append(linkifyBareURLs(String(remaining), linkColor: linkColor))
                break
            }
        }
        return result
    }

    // MARK: - Parsing

    private struct MarkdownMatch {
        let range: Range<String.SubSequence.Index>
        let label: String
        let url: String
    }

    private static func firstMarkdownLink(in text: Substring) -> MarkdownMatch? {
        // [label](url) — label cannot contain ]; url is taken until ).
        guard let regex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#
        ) else { return nil }

        let ns = NSString(string: String(text))
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: String(text), options: [], range: full),
              match.numberOfRanges == 3,
              let fullRange = Range(match.range, in: text),
              let labelRange = Range(match.range(at: 1), in: text),
              let urlRange = Range(match.range(at: 2), in: text)
        else { return nil }

        return MarkdownMatch(
            range: fullRange,
            label: String(text[labelRange]),
            url: String(text[urlRange])
        )
    }

    private static let bareURLPattern =
        #"((?:https?://|www\.)[^\s<]+|(?<![@\w.])(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+(?:com|org|net|io|co|edu|gov|info|me|app|dev|us|uk|ca|au|ngo|fund|charity|foundation)(?:/[^\s<]*)?)"#

    private static func linkifyBareURLs(_ text: String, linkColor: Color) -> AttributedString {
        guard let regex = try? NSRegularExpression(pattern: bareURLPattern, options: [.caseInsensitive]) else {
            return AttributedString(text)
        }

        var result = AttributedString()
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var cursor = 0

        for match in regex.matches(in: text, options: [], range: full) {
            if match.range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result.append(AttributedString(plain))
            }

            var raw = ns.substring(with: match.range)
            var trailing = ""
            while let last = raw.last, "),.!?;:".contains(last) {
                trailing = String(last) + trailing
                raw.removeLast()
            }

            var linkText = AttributedString(raw)
            if let url = normalizedURL(raw) {
                linkText.link = url
                linkText.foregroundColor = linkColor
                linkText.underlineStyle = .single
            }
            result.append(linkText)
            if !trailing.isEmpty {
                result.append(AttributedString(trailing))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            result.append(AttributedString(ns.substring(from: cursor)))
        }
        return result
    }

    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return nil
            }
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    /// Builds a markdown link, normalizing the URL to https when needed.
    static func markdownLink(label: String, urlRaw: String) -> String? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty,
              let url = normalizedURL(urlRaw),
              let href = url.absoluteString as String?
        else { return nil }
        let safeLabel = label
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return "[\(safeLabel)](\(href))"
    }
}
