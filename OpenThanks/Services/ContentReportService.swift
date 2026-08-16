import Foundation

/// Submits UGC reports to openthanks.com (App Store Guideline 1.2).
enum ContentReportService {
    enum Target: Equatable {
        case gratitude(UUID)
        case profile(UUID)

        var typeKey: String {
            switch self {
            case .gratitude: "gratitude"
            case .profile: "profile"
            }
        }

        var id: UUID {
            switch self {
            case .gratitude(let id), .profile(let id): id
            }
        }
    }

    enum Reason: String, CaseIterable, Identifiable {
        case spam
        case harassment
        case inappropriate
        case impersonation
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spam: "Spam or scam"
            case .harassment: "Harassment or bullying"
            case .inappropriate: "Inappropriate content"
            case .impersonation: "Impersonation"
            case .other: "Something else"
            }
        }
    }

    enum ReportError: LocalizedError {
        case notSignedIn
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "Sign in to report content."
            case .server(let message):
                message
            }
        }
    }

    static func submit(
        target: Target,
        reason: Reason,
        details: String?
    ) async throws {
        guard let session = try? await supabase.auth.session else {
            throw ReportError.notSignedIn
        }

        var request = URLRequest(url: AppConfig.webAppURL.appending(path: "api/report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        struct Body: Encodable {
            let target_type: String
            let target_id: String
            let reason: String
            let details: String?
        }

        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        request.httpBody = try JSONEncoder().encode(
            Body(
                target_type: target.typeKey,
                target_id: target.id.uuidString.lowercased(),
                reason: reason.rawValue,
                details: (trimmed?.isEmpty == false) ? trimmed : nil
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            struct APIError: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error
            throw ReportError.server(message ?? "Couldn't send your report. Try again.")
        }
    }
}
