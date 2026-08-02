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

    private var hasAvatar: Bool {
        photoData != nil || auth.currentProfile?.avatarURL != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    profilePhotoRow
                    TextField("Full name", text: $fullName)
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(Theme.textSecondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !required {
                        TextField("Headline", text: $headline)
                    }
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
                        Text("Add your name and username to enter OpenThanks. A profile photo is optional.")
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
                    Button(required ? "Continue" : "Save") { Task { await save() } }
                        .disabled(saving || loadingPhoto || cleanUsername.isEmpty || cleanFullName.isEmpty)
                        .foregroundStyle(Theme.coral)
                }
            }
            .onAppear {
                let p = auth.currentProfile
                fullName = p?.fullName ?? ""
                username = p?.username ?? ""
                headline = p?.headline ?? ""
                nonprofitEin = p?.favoriteNonprofitEin
                nonprofitName = p?.favoriteNonprofitName
                nonprofitWebsite = p?.favoriteNonprofitWebsite
                nonprofitWhy = p?.favoriteNonprofitHeadline ?? ""
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

            if hasAvatar {
                Button {
                    openCropEditor()
                } label: {
                    Label("Adjust photo", systemImage: "crop")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .disabled(loadingPhoto)
                .accessibilityLabel("Adjust profile photo crop")
            }
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

    private func openCropEditor() {
        if let source = editableSourceImage {
            cropItem = CropItem(image: source)
            return
        }
        if let photoData, let image = UIImage(data: photoData)?.normalizedOrientation() {
            editableSourceImage = image
            cropItem = CropItem(image: image)
            return
        }
        // Existing remote avatar — load, then crop.
        guard let url = auth.currentProfile?.avatarURL else { return }
        loadingPhoto = true
        Task {
            defer { loadingPhoto = false }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let prepared = await ImageProcessing.prepareForEditing(data)
            else {
                errorMessage = "Couldn't load your current photo to adjust."
                return
            }
            editableSourceImage = prepared
            cropItem = CropItem(image: prepared)
        }
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
                    avatarUrl: avatarURLString
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
