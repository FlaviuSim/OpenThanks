import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device rewrites via Apple Intelligence (Foundation Models). No network calls.
enum AppreciationAI {
    enum Style: String, CaseIterable, Identifiable {
        case polish
        case shorten
        case warmer

        var id: String { rawValue }

        var buttonTitle: String {
            switch self {
            case .polish: "Polish"
            case .shorten: "Shorten"
            case .warmer: "Make it warmer"
            }
        }

        var busyTitle: String {
            switch self {
            case .polish: "Polishing…"
            case .shorten: "Shortening…"
            case .warmer: "Warming up…"
            }
        }
    }

    enum AIError: LocalizedError {
        case emptyMessage
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .emptyMessage:
                "Write a few words first, then tap an AI suggestion."
            case .unavailable:
                "Apple Intelligence isn’t available on this device yet."
            case .failed(let message):
                message
            }
        }
    }

    /// True when the on-device model can run (Apple Intelligence device + ready).
    /// Prefer calling this off the main path when opening UI — the system check can be slow.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            default:
                return false
            }
        }
        #endif
        return false
    }

    static func rewrite(_ text: String, style: Style) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyMessage }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIError.unavailable
            }
            let session = LanguageModelSession(instructions: instructions(for: style))
            let response = try await session.respond(to: trimmed)
            let content = String(response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw AIError.failed("Apple Intelligence returned an empty suggestion. Try again.")
            }
            return content
        }
        #endif
        throw AIError.unavailable
    }

    private static func instructions(for style: Style) -> String {
        let shared = """
            You help people write sincere thank-you notes on OpenThanks.
            Preserve the original meaning, specific details, and the sender's voice.
            Do not add greetings, sign-offs, quotes, or commentary — return only the rewritten message.
            Stay genuine; never sound fake, salesy, or overly dramatic.
            """
        switch style {
        case .polish:
            return """
            \(shared)
            Rewrite the user's message so it reads clearly and smoothly — polished but not cheesy.
            Fix awkward phrasing while keeping roughly the same length and their natural voice.
            """
        case .shorten:
            return """
            \(shared)
            Rewrite the user's message to be shorter and tighter.
            Cut filler and repetition while keeping the heart of the thank-you and any concrete details.
            Aim for noticeably fewer words — about half the length when possible, without losing sincerity.
            """
        case .warmer:
            return """
            \(shared)
            Rewrite the user's message so it feels warmer and more heartfelt.
            Keep their meaning and approximate length.
            """
        }
    }
}
