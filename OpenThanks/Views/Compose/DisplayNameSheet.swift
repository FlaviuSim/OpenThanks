import SwiftUI

/// Quick name capture before sending — keeps first-run soft while blocking blank authors.
struct DisplayNameSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var cleanName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool { !cleanName.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What’s your name?")
                                .font(Theme.display(28, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("People see who their thank-you is from. A first name is enough.")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)

                        TextField("Your name", text: $fullName)
                            .textInputAutocapitalization(.words)
                            .textContentType(.name)
                            .focused($nameFocused)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(nameFocused ? Theme.coral.opacity(0.45) : Theme.hairline)
                            )
                            .submitLabel(.done)
                            .onSubmit {
                                guard canContinue, !saving else { return }
                                Task { await save() }
                            }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.body(13))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 8) {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: 10) {
                            if saving {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color(hex: 0x2B1209))
                            }
                            Text(saving ? "Saving…" : "Continue")
                        }
                    }
                    .buttonStyle(CTAButtonStyle(isLoading: saving, isEnabled: canContinue))
                    .disabled(saving || !canContinue)
                    .accessibilityHint(canContinue ? "Saves your name and returns to compose" : "Enter your name to continue")
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(Theme.background.opacity(0.96))
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Your name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .readableWidth()
            .onAppear {
                let existing = auth.currentProfile?.fullName?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !existing.isEmpty {
                    fullName = existing
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    nameFocused = true
                }
            }
            .syncAppAppearance()
        }
    }

    private func save() async {
        guard let userId = auth.userId, canContinue else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let username = auth.currentProfile?.username
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !username.isEmpty else {
                errorMessage = "Couldn't update your profile. Try again from Settings."
                return
            }
            let update = GratitudeService.ProfileUpdate(
                fullName: cleanName,
                username: username,
                avatarUrl: auth.currentProfile?.avatarUrl,
                headline: auth.currentProfile?.headline
            )
            let updated = try await GratitudeService.updateProfile(userId: userId, update: update)
            auth.currentProfile = updated
            NotificationCenter.default.post(name: .profileDidUpdate, object: updated)
            Analytics.capture("compose_display_name_saved")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
