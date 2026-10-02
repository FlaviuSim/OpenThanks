import Foundation

/// Posts private in-app feedback to the website support inbox.
enum SupportFeedbackService {
    enum FeedbackError: LocalizedError {
        case invalidEmail
        case messageTooShort
        case server(String)
        case network

        var errorDescription: String? {
            switch self {
            case .invalidEmail: "Please enter a valid email address."
            case .messageTooShort: "Please write a bit more so we can help."
            case .server(let message): message
            case .network: "Couldn't send right now. Please try again or email founders@openthanks.com."
            }
        }
    }

    static func send(
        name: String?,
        email: String,
        message: String,
        subject: String = "In-app feedback"
    ) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            throw FeedbackError.invalidEmail
        }
        guard trimmedMessage.count >= 10 else {
            throw FeedbackError.messageTooShort
        }

        var request = URLRequest(url: AppConfig.webAppURL.appending(path: "api/support"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "name": name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "email": trimmedEmail,
            "subject": subject,
            "message": trimmedMessage,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FeedbackError.network }
            if (200..<300).contains(http.statusCode) { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String,
               !error.isEmpty {
                throw FeedbackError.server(error)
            }
            throw FeedbackError.network
        } catch let error as FeedbackError {
            throw error
        } catch {
            throw FeedbackError.network
        }
    }
}
