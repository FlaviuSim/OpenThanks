import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device rewrites via Apple Intelligence (Foundation Models). No network calls.
enum AppreciationAI {
    enum Style: String {
        case warmer
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
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
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
        switch style {
        case .warmer:
            """
            You help people write sincere thank-you notes on OpenThanks.
            Rewrite the user's message so it feels warmer and more heartfelt.
            Keep their meaning, voice, and approximate length.
            Do not add greetings, sign-offs, quotes, or commentary — return only the rewritten message.
            Stay genuine; never sound fake, salesy, or overly dramatic.
            """
        }
    }
}
