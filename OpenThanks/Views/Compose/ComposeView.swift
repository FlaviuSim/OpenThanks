import SwiftUI
import PhotosUI

struct ComposeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var recipient = ""
    @State private var message = ""
    @State private var visibility: GratitudeVisibility = .public
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    private let maxLength = 1500

    var body: some View {
        NavigationStack {
            if sent {
                SuccessView(onShareAnother: reset, onDone: { dismiss() })
            } else {
                form
            }
        }
        .background(Theme.background)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                field(label: "Who are you thanking?") {
                    TextField("Name, email, phone, or leave blank", text: $recipient)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.textPrimary)
                }

                field(label: "Your message") {
                    VStack(alignment: .trailing, spacing: 6) {
                        TextEditor(text: $message)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .overlay(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("What would you like to say?")
                                        .foregroundStyle(Theme.textTertiary)
                                        .padding(.top, 18).padding(.leading, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                        Text("\(message.count)/\(maxLength)")
                            .font(Theme.body(12))
                            .foregroundStyle(message.count > maxLength ? .red : Theme.textTertiary)
                    }
                }

                if AppConfig.polishEndpoint != nil {
                    HStack(spacing: 10) {
                        polishButton("Make it Warmer", icon: "sparkles")
                        polishButton("Polish for public", icon: "wand.and.stars")
                    }
                }

                field(label: "Add a photo") {
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoData == nil ? "Library" : "Change photo",
                                  systemImage: "photo.on.rectangle")
                                .font(Theme.body(15, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                        if photoData != nil {
                            Button {
                                photoData = nil; photoItem = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(14)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }

                if let photoData, let ui = UIImage(data: photoData) {
                    Image(uiImage: ui)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Visibility row per mockup footer
                Button {
                    visibility = visibility == .public ? .private : .public
                } label: {
                    HStack {
                        Image(systemName: visibility == .public ? "globe" : "lock.fill")
                            .foregroundStyle(Theme.textSecondary)
                        Text(visibility == .public
                             ? "Anyone on OpenThanks can see this."
                             : "Only the recipient can see this.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("Change")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }

                if let error {
                    Text(error).font(Theme.body(13)).foregroundStyle(.red)
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle("New Appreciation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
            }
            ToolbarItem(placement: .confirmationAction) {
                if sending {
                    ProgressView().tint(Theme.coral)
                } else {
                    Button("Send") { Task { await send() } }
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(canSend ? Theme.coral : Theme.textTertiary)
                        .disabled(!canSend)
                }
            }
        }
        .onChange(of: photoItem) {
            Task { photoData = try? await photoItem?.loadTransferable(type: Data.self) }
        }
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    private func field(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
    }

    private func polishButton(_ title: String, icon: String) -> some View {
        Button {
            // Wire to AppConfig.polishEndpoint (Next.js API route) when ready.
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Send

    private func send() async {
        guard let userId = auth.userId else { return }
        sending = true; error = nil
        do {
            var mediaUrl: String?
            var mediaType: String?
            if let photoData {
                let url = try await GratitudeService.uploadMedia(
                    data: photoData, contentType: "image/jpeg", userId: userId)
                mediaUrl = url.absoluteString
                mediaType = "image"
            }
            let contact = parseRecipient(recipient)
            let new = NewGratitude(
                authorId: userId,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                recipientEmail: contact.email,
                recipientPhone: contact.phone,
                recipientName: contact.name,
                visibility: visibility.rawValue,
                mediaUrl: mediaUrl,
                mediaType: mediaType,
                source: "ios"
            )
            _ = try await GratitudeService.create(new)
            sent = true
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }

    private func parseRecipient(_ raw: String)
        -> (name: String?, email: String?, phone: String?) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil, nil) }
        if value.contains("@") { return (nil, value.lowercased(), nil) }
        let digits = value.filter { $0.isNumber }
        if digits.count >= 7 && value.allSatisfy({ "+()- 0123456789".contains($0) }) {
            let e164 = value.hasPrefix("+") ? "+" + digits : "+1" + digits
            return (nil, nil, e164)
        }
        return (value, nil, nil)
    }

    private func reset() {
        recipient = ""; message = ""; photoData = nil; photoItem = nil
        visibility = .public; sent = false
    }
}

struct SuccessView: View {
    var onShareAnother: () -> Void
    var onDone: () -> Void
    @State private var burst = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            HeartMark(size: 96)
                .scaleEffect(burst ? 1 : 0.4)
                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: burst)
            VStack(spacing: 8) {
                Text("Your appreciation\nhas been shared!")
                    .font(Theme.display(28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("You just brightened someone's day and inspired others.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Button("View in Feed", action: onDone)
                .buttonStyle(CTAButtonStyle())
                .padding(.horizontal, 24)
            Button("Share Another", action: onShareAnother)
                .font(Theme.body(16, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .onAppear { burst = true }
    }
}
