import SwiftUI
import PhotosUI
import UIKit

struct EditProfileSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var required = false
    @State private var fullName = ""
    @State private var username = ""
    @State private var headline = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    /// Full image kept so the cropper can be reopened after picking.
    @State private var editableSourceImage: UIImage?
    @State private var cropItem: CropItem?
    @State private var loadingPhoto = false
    @State private var nonprofitEin: String?
    @State private var nonprofitName: String?
    @State private var nonprofitWebsite: String?
    @State private var nonprofitWhy = ""
    @State private var nonprofitQuery = ""
    @State private var nonprofitResults: [NonprofitOrg] = []
    @State private var searching = false
    @State private var saving = false
    @State private var errorMessage: String?
    /// When Sign in with Apple already supplied the name, keep it and only ask for username.
    @State private var nameLockedFromApple = false

    private struct CropItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var cleanUsername: String {
        username.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private var cleanFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !cleanUsername.isEmpty && !cleanFullName.isEmpty
    }

    private var continueBlockedHint: String {
        if cleanFullName.isEmpty && cleanUsername.isEmpty {
            return "Enter your name and username to continue"
        }
        if cleanFullName.isEmpty { return "Enter your name to continue" }
        if cleanUsername.isEmpty { return "Enter a username to continue" }
        return ""
    }

    private var requiredHelperCopy: String {
        if nameLockedFromApple {
            return "Your name came from Sign in with Apple. Choose a username to finish — photo and headline are optional."
        }
        if !cleanFullName.isEmpty {
            return "Choose a username to enter OpenThanks. Photo and headline are optional."
        }
        return "Add your name and username to enter OpenThanks. Photo and headline are optional."
    }

    private var hasAvatar: Bool {
        photoData != nil || auth.currentProfile?.avatarURL != nil
    }

    private func applyProfileFields(from p: Profile?) {
        fullName = p?.fullName ?? fullName
        username = p?.username ?? username
        headline = p?.headline ?? headline
        nonprofitEin = p?.favoriteNonprofitEin
        nonprofitName = p?.favoriteNonprofitName
        nonprofitWebsite = p?.favoriteNonprofitWebsite
        nonprofitWhy = p?.favoriteNonprofitHeadline ?? ""
        // Apple already provided the name — don't make reviewers re-type it.
        nameLockedFromApple = required && !cleanFullName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    profilePhotoRow
                    TextField("Full name", text: $fullName)
                        .disabled(nameLockedFromApple)
                        .foregroundStyle(nameLockedFromApple ? Theme.textSecondary : Theme.textPrimary)
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(Theme.textSecondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField(required ? "Headline (optional)" : "Headline", text: $headline)
                }
                .listRowBackground(Theme.surface)

                if !required {
                    nonprofitSection
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(Theme.body(13))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Theme.surface)
                }

                if required {
                    Section {
                        Text(requiredHelperCopy)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(required ? "Complete Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !required {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !required {
                        Button("Save") { Task { await save() } }
                            .disabled(saving || loadingPhoto || !canContinue)
                            .foregroundStyle(canContinue ? Theme.coral : Theme.textTertiary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if required {
                    VStack(spacing: 8) {
                        if !canContinue, !continueBlockedHint.isEmpty {
                            Text(continueBlockedHint)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CTAButtonStyle(isLoading: saving))
                        .disabled(saving || loadingPhoto || !canContinue)
                        .opacity(canContinue || saving ? 1 : 0.45)
                        .accessibilityHint(canContinue ? "" : continueBlockedHint)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(Theme.background.opacity(0.96))
                }
            }
            .readableWidth()
            .onAppear {
                applyProfileFields(from: auth.currentProfile)
            }
            .onChange(of: auth.currentProfile?.fullName) { _, newName in
                // Late Apple name/email sync — unlock Continue without retyping.
                guard required else { return }
                let incoming = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !incoming.isEmpty else { return }
                if cleanFullName.isEmpty {
                    fullName = incoming
                }
                if !cleanFullName.isEmpty {
                    nameLockedFromApple = true
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await handlePickedPhoto(item) }
            }
            .fullScreenCover(item: $cropItem) { item in
                ImageCropperView(
                    image: item.image,
                    cropAspectRatio: 1,
                    circularGuide: true,
                    onCancel: {
                        cropItem = nil
                        photoItem = nil
                    },
                    onCrop: { cropped in
                        applyCroppedAvatar(cropped, source: item.image)
                        cropItem = nil
                        photoItem = nil
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var profilePhotoRow: some View {
        VStack(spacing: 12) {
            Group {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let avatarURL = auth.currentProfile?.avatarURL {
                    CachedAsyncImage(url: avatarURL, maxPixelSize: RemoteImageCache.avatarMaxPixelSize) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.heartGradient, lineWidth: 2))
            .frame(maxWidth: .infinity)
            .opacity(loadingPhoto ? 0.55 : 1)

            if loadingPhoto {
                ProgressView()
                    .tint(Theme.coral)
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(hasAvatar ? "Change Profile Photo" : "Add Profile Photo (optional)")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
            }
            .disabled(loadingPhoto)
        }
        .padding(.vertical, 8)
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Theme.surfaceRaised)
            Image(systemName: "person.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var nonprofitSection: some View {
        Section("Nonprofit you champion") {
            if let nonprofitName {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nonprofitName)
                            .font(Theme.body(15, weight: .semibold))
                        if let nonprofitEin, nonprofitEin != "custom" {
                            Text("EIN \(nonprofitEin)")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        self.nonprofitName = nil
                        nonprofitEin = nil
                        nonprofitWebsite = nil
                        nonprofitWhy = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                TextField(
                    "Nonprofit website",
                    text: Binding(
                        get: { nonprofitWebsite ?? "" },
                        set: { nonprofitWebsite = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .onSubmit { normalizeNonprofitWebsite() }
                TextField(
                    "Why this cause? (shown on your profile)",
                    text: $nonprofitWhy,
                    axis: .vertical
                )
                .lineLimit(2...4)
            } else {
                HStack {
                    TextField("Search nonprofits…", text: $nonprofitQuery)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await searchNonprofits() } }
                    Button {
                        Task { await searchNonprofits() }
                    } label: {
                        if searching {
                            ProgressView().tint(Theme.coral)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.coral)
                        }
                    }
                    .disabled(nonprofitQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(nonprofitResults.prefix(8)) { org in
                    Button {
                        nonprofitEin = org.strein
                        nonprofitName = org.name
                        // Match web: user enters the org's own site (not ProPublica).
                        nonprofitWebsite = ""
                        nonprofitResults = []
                        nonprofitQuery = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(org.name)
                                .font(Theme.body(14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            if let location = org.location {
                                Text(location)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Photo crop

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        errorMessage = nil
        defer { loadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't load that photo. Try another one."
                photoItem = nil
                return
            }
            guard let prepared = await ImageProcessing.prepareForEditing(data) else {
                errorMessage = "That image couldn't be opened. Try a different photo."
                photoItem = nil
                return
            }
            editableSourceImage = prepared
            cropItem = CropItem(image: prepared)
        } catch {
            errorMessage = "Couldn't load that photo. Try another one."
            photoItem = nil
        }
    }

    private func applyCroppedAvatar(_ image: UIImage, source: UIImage) {
        editableSourceImage = source
        if let jpeg = ImageProcessing.jpegForAvatar(image) {
            photoData = jpeg
        } else if let jpeg = image.downsampled(maxDimension: ImageProcessing.avatarMaxDimension)
            .jpegData(compressionQuality: ImageProcessing.avatarJPEGQuality) {
            photoData = jpeg
        }
        errorMessage = nil
    }

    private func normalizeNonprofitWebsite() {
        let trimmed = (nonprofitWebsite ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nonprofitWebsite = nil
            return
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            nonprofitWebsite = trimmed
        } else {
            nonprofitWebsite = "https://\(trimmed)"
        }
    }

    private func searchNonprofits() async {
        let query = nonprofitQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searching = true
        nonprofitResults = (try? await GratitudeService.searchNonprofits(query: query)) ?? []
        searching = false
    }

    private func save() async {
        guard let userId = auth.userId else { return }
        saving = true
        errorMessage = nil
        do {
            var avatarURLString = auth.currentProfile?.avatarUrl
            if let photoData {
                guard let image = UIImage(data: photoData),
                      let jpegData = ImageProcessing.jpegForAvatar(image) else {
                    throw URLError(.cannotDecodeContentData)
                }
                avatarURLString = try await GratitudeService.uploadAvatar(
                    data: jpegData,
                    contentType: "image/jpeg",
                    userId: userId
                ).absoluteString
            }
            let update: GratitudeService.ProfileUpdate
            if required {
                update = .init(
                    fullName: cleanFullName,
                    username: cleanUsername,
                    avatarUrl: avatarURLString,
                    headline: headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : headline.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } else {
                if nonprofitName != nil {
                    normalizeNonprofitWebsite()
                    let site = (nonprofitWebsite ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if site.isEmpty {
                        errorMessage = "Add the nonprofit's website."
                        saving = false
                        return
                    }
                }
                update = .init(
                    fullName: cleanFullName,
                    username: cleanUsername,
                    avatarUrl: avatarURLString,
                    headline: headline.isEmpty ? nil : headline,
                    favoriteNonprofitEin: nonprofitEin,
                    favoriteNonprofitName: nonprofitName,
                    favoriteNonprofitWebsite: nonprofitWebsite,
                    favoriteNonprofitHeadline: nonprofitName == nil || nonprofitWhy.isEmpty
                        ? nil : nonprofitWhy,
                    clearOptionalFields: true
                )
            }
            let updated = try await GratitudeService.updateProfile(userId: userId, update: update)
            auth.currentProfile = updated
            NotificationCenter.default.post(name: .profileDidUpdate, object: updated)
            if !required { dismiss() }
        } catch {
            errorMessage = error.localizedDescription.localizedCaseInsensitiveContains("duplicate")
                || error.localizedDescription.localizedCaseInsensitiveContains("unique")
                ? "That username is already taken."
                : error.localizedDescription
        }
        saving = false
    }
}
