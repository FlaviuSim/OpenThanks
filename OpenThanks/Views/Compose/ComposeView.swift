import SwiftUI
import PhotosUI

struct ComposeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// When set, the form edits this pending appreciation instead of creating one.
    var editing: Gratitude? = nil
    /// Prefills the recipient field (e.g. from Home people search invite).
    var initialRecipient: String? = nil
    /// Prefills and links an existing member (e.g. Thank from their profile).
    var initialRecipientProfile: Profile? = nil
    /// Prefills the message (e.g. Siri “thank … for …”).
    var initialMessage: String? = nil
    /// App Group image from the Share Extension.
    var initialImageFileName: String? = nil
    var onSaved: ((Gratitude) -> Void)? = nil

    @State private var recipient = ""
    @State private var message = ""
    @State private var visibility: GratitudeVisibility = .public
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: UIImage?
    @State private var existingMediaUrl: String?
    @State private var existingMediaType: String?
    @State private var removedPhoto = false
    @State private var cropItem: CropItem?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false
    @State private var created: Gratitude?
    /// Edit target after a successful send (or the incoming `editing` value).
    @State private var activeEditing: Gratitude?
    @State private var polishing: AppreciationAI.Style?
    @State private var messageBeforeAI: String?
    @State private var didPrefill = false
    /// Kept so create can set `recipient_id` even if the typed field is a name.
    @State private var linkedRecipient: Profile?
    /// Email for the linked member — loaded eagerly so claim mail can send
    /// even when the profile object passed into compose has no email.
    @State private var linkedRecipientEmail: String?
    @State private var recipientResults: [Profile] = []
    @State private var recipientSearching = false
    @State private var recipientDidSearch = false
    @FocusState private var messageFocused: Bool
    @FocusState private var recipientFocused: Bool

    private let maxLength = 1500
    private let quickEmojis = ["🙏", "❤️", "🫶", "🥰", "🤗", "✨", "🌟", "💐"]
    private var editingTarget: Gratitude? { activeEditing ?? editing }
    private var isEditing: Bool { editingTarget != nil }

    private struct CropItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        NavigationStack {
            if sent, let created, activeEditing == nil {
                SuccessView(
                    gratitude: created,
                    onEdit: { beginEditing(created) },
                    onDone: { dismiss() }
                )
            } else {
                form
            }
        }
        .background(Theme.background)
        .fullScreenCover(item: $cropItem) { item in
            ImageCropperView(
                image: item.image,
                onCancel: {
                    cropItem = nil
                    photoItem = nil
                    messageFocused = true
                },
                onCrop: { cropped in
                    applyCroppedPhoto(cropped)
                    cropItem = nil
                    photoItem = nil
                    messageFocused = true
                }
            )
            .ignoresSafeArea()
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    intro

                    recipientSection

                    messageSection

                    photoSection

                    visibilitySection

                    if let error {
                        Text(error)
                            .font(Theme.body(13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)

            sendBar
        }
        .background(Theme.background)
        .navigationTitle(isEditing ? "Edit Appreciation" : "New Appreciation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.textSecondary)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    messageFocused = false
                    recipientFocused = false
                }
                .font(Theme.body(16, weight: .semibold))
                .foregroundStyle(Theme.coral)
            }
        }
        .onAppear { prefillIfNeeded() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isEditing ? "Edit your appreciation" : "Share something kind")
                .font(Theme.display(26, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(isEditing
                 ? "Update the message or details before they claim it."
                 : "A few sincere words can stay with someone for years.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Who are you thanking?")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Optional")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                recipientFieldChrome

                if linkedRecipient == nil, showRecipientSuggestions {
                    recipientSuggestions
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showRecipientSuggestions)
            .animation(.easeInOut(duration: 0.18), value: linkedRecipient?.id)
        }
        .task(id: recipientSearchQuery) {
            await runRecipientSearch(for: recipientSearchQuery)
        }
    }

    private var recipientFieldChrome: some View {
        Group {
            if let linked = linkedRecipient {
                HStack(spacing: 10) {
                    linkedRecipientChip(linked)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                TextField("Name, @username, email, or leave blank", text: $recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.default)
                    .textContentType(.none)
                    .focused($recipientFocused)
                    .padding(14)
                    .foregroundStyle(Theme.textPrimary)
                    .submitLabel(.done)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    recipientFocused && linkedRecipient == nil
                        ? Theme.coral.opacity(0.45)
                        : Theme.hairline,
                    lineWidth: 1
                )
        )
    }

    private func linkedRecipientChip(_ profile: Profile) -> some View {
        HStack(spacing: 8) {
            AvatarView(profile: profile, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(chipLabel(for: profile))
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let fullName = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !fullName.isEmpty,
                   !profile.username.isEmpty {
                    Text(fullName)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Button {
                clearLinkedRecipient(focusField: true)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove recipient")
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(Theme.coralPale.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recipient \(chipLabel(for: profile))")
    }

    private var recipientSuggestions: some View {
        VStack(spacing: 0) {
            if recipientSearching && recipientResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.coral).controlSize(.small)
                    Text("Searching…")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(14)
            } else if !recipientResults.isEmpty {
                ForEach(Array(recipientResults.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        selectLinkedRecipient(profile)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(profile: profile, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                if !profile.username.isEmpty {
                                    Text("@\(profile.username)")
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.coral)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < recipientResults.count - 1 {
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 0.5)
                            .padding(.leading, 66)
                    }
                }
            } else if recipientDidSearch {
                VStack(alignment: .leading, spacing: 6) {
                    Text(inviteSuggestionTitle)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("We’ll send a claim link when you share — email, name, or leave blank all work.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
    }

    private var recipientSearchQuery: String {
        guard linkedRecipient == nil else { return "" }
        return recipient.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showRecipientSuggestions: Bool {
        linkedRecipient == nil
            && recipientFocused
            && recipientSearchQuery.count >= 2
    }

    private var inviteSuggestionTitle: String {
        let q = recipientSearchQuery
        if looksLikeEmail(q) {
            return "Invite \(q)"
        }
        if q.hasPrefix("@") {
            return "No one with that username yet — keep typing an email or name to invite"
        }
        return "Invite “\(q)”"
    }

    private func chipLabel(for profile: Profile) -> String {
        let handle = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !handle.isEmpty { return "@\(handle)" }
        return profile.displayName
    }

    private func selectLinkedRecipient(_ profile: Profile) {
        linkedRecipient = profile
        recipient = ""
        recipientResults = []
        recipientSearching = false
        recipientDidSearch = false
        recipientFocused = false
        if let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            linkedRecipientEmail = AuthService.normalizedEmail(email)
        } else {
            linkedRecipientEmail = nil
        }
        Task { await loadLinkedRecipientContact(profileId: profile.id) }
    }

    private func clearLinkedRecipient(focusField: Bool) {
        linkedRecipient = nil
        linkedRecipientEmail = nil
        recipient = ""
        if focusField {
            recipientFocused = true
        }
    }

    private func runRecipientSearch(for current: String) async {
        guard linkedRecipient == nil, current.count >= 2 else {
            recipientResults = []
            recipientSearching = false
            recipientDidSearch = false
            return
        }

        recipientSearching = true
        recipientDidSearch = false
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        let query = current.hasPrefix("@") ? String(current.dropFirst()) : current
        guard query.count >= 2 else {
            recipientResults = []
            recipientSearching = false
            recipientDidSearch = false
            return
        }

        do {
            let found = try await GratitudeService.searchProfiles(query: query)
            guard !Task.isCancelled else { return }
            let selfId = auth.userId
            recipientResults = found.filter { $0.id != selfId }
            recipientDidSearch = true
        } catch {
            if !error.isCancellation {
                recipientResults = []
                recipientDidSearch = true
            }
        }
        recipientSearching = false
    }

    private var messageSection: some View {
        field(label: "Your message") {
            VStack(spacing: 0) {
                TextEditor(text: $message)
                    .focused($messageFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .foregroundStyle(Theme.textPrimary)
                    .disabled(loadingPhoto || sending || polishing != nil)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("What would you like to say?")
                                .font(Theme.body(16))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 18)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    }

                Divider().overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: 12) {
                    emojiShortcuts

                    HStack(alignment: .center, spacing: 10) {
                        if AppreciationAI.isAvailable {
                            aiChip
                        }

                        Spacer(minLength: 8)

                        if messageBeforeAI != nil {
                            Button("Undo") {
                                if let previous = messageBeforeAI {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        message = previous
                                        messageBeforeAI = nil
                                    }
                                }
                            }
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                        }

                        Text("\(message.count)/\(maxLength)")
                            .font(Theme.body(12).monospacedDigit())
                            .foregroundStyle(message.count > maxLength ? .red : Theme.textTertiary)
                    }
                }
                .padding(12)
            }
        }
    }

    private var photoSection: some View {
        field(label: "Photo", hint: "Optional") {
            if let photoPreview {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photoPreview)
                        .resizable()
                        .flexiblePhotoPreview(maxHeight: 420)

                    HStack(spacing: 8) {
                        PhotosPicker(
                            selection: $photoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                        .disabled(loadingPhoto || sending)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { clearPhoto() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .disabled(loadingPhoto || sending)
                        .accessibilityLabel("Remove photo")
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                PhotosPicker(
                    selection: $photoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 14) {
                        ZStack {
                            if loadingPhoto {
                                Circle()
                                    .fill(Theme.coral)
                                    .frame(width: 46, height: 46)
                                ProgressView().tint(.white)
                            } else {
                                ActionGlyph(systemImage: "photo")
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(loadingPhoto ? "Preparing photo…" : "Add a photo")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Crop it to look great in the feed")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(loadingPhoto || sending)
            }

            if let photoError {
                Text(photoError)
                    .font(Theme.body(12))
                    .foregroundStyle(.red)
            }
        }
    }

    private var visibilitySection: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                visibility = visibility == .public ? .private : .public
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.surfaceRaised)
                        .frame(width: 40, height: 40)
                    Image(systemName: visibility == .public ? "globe" : "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(visibility == .public ? "Public" : "Private")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(visibility == .public
                         ? "Anyone on OpenThanks can see this"
                         : "Only you and the recipient can see this")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Text("Switch")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .sensoryFeedback(.selection, trigger: visibility)
    }

    private var sendBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)

            Button {
                messageFocused = false
                recipientFocused = false
                Task { await send() }
            } label: {
                HStack(spacing: 8) {
                    if sending {
                        ProgressView()
                            .tint(Color(hex: 0x2B1209))
                    } else {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(sending
                         ? (isEditing ? "Saving…" : "Sending…")
                         : (isEditing ? "Save Changes" : "Send Appreciation"))
                }
            }
            .buttonStyle(CTAButtonStyle(isLoading: sending))
            .disabled(!canSend || sending)
            .opacity(canSend || sending ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(Theme.background.opacity(0.96))
    }

    // MARK: Message tools

    private var emojiShortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button {
                        insertEmoji(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 22))
                            .frame(width: 40, height: 40)
                            .background(Theme.coralPale.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(ScalePressButtonStyle())
                    .accessibilityLabel("Insert \(emoji)")
                }
            }
        }
        .disabled(sending || polishing != nil)
    }

    private var aiChip: some View {
        let isBusy = polishing != nil
        return Button {
            Task { await runAI(.warmer) }
        } label: {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color(hex: 0x2B1209))
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(isBusy ? "Warming up…" : "Make it warmer")
                    .font(Theme.body(13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(hex: 0x2B1209))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.coralPale, in: Capsule())
        }
        .buttonStyle(ScalePressButtonStyle())
        .disabled(
            polishing != nil
                || sending
                || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    // MARK: Chrome helpers

    private func field(
        label: String,
        hint: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let hint {
                    Text(hint)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            content()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )
        }
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength && !loadingPhoto && polishing == nil
    }

    private func insertEmoji(_ emoji: String) {
        messageFocused = true
        if message.isEmpty || message.hasSuffix(" ") || message.hasSuffix("\n") {
            message += emoji
        } else {
            message += " \(emoji)"
        }
        if message.count > maxLength {
            message = String(message.prefix(maxLength))
        }
    }

    private func runAI(_ style: AppreciationAI.Style) async {
        guard polishing == nil else { return }
        polishing = style
        error = nil
        messageFocused = false
        defer { polishing = nil }
        do {
            let original = message
            let rewritten = try await AppreciationAI.rewrite(original, style: style)
            withAnimation(.easeInOut(duration: 0.2)) {
                messageBeforeAI = original
                message = String(rewritten.prefix(maxLength))
            }
            messageFocused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Photo

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        photoError = nil
        messageFocused = false
        recipientFocused = false
        defer { loadingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "Couldn't load that photo. Try another one."
                photoItem = nil
                return
            }
            guard let prepared = await ImageProcessing.prepareForEditing(data) else {
                photoError = "That image couldn't be opened. Try a different photo."
                photoItem = nil
                return
            }
            cropItem = CropItem(image: prepared)
        } catch {
            photoError = "Couldn't load that photo. Try another one."
            photoItem = nil
        }
    }

    private func applyCroppedPhoto(_ image: UIImage) {
        if let jpeg = ImageProcessing.jpegForUpload(image) {
            photoData = jpeg
            photoPreview = UIImage(data: jpeg) ?? image.downsampled(maxDimension: 720)
        } else if let jpeg = image.downsampled(maxDimension: ImageProcessing.postMaxDimension)
            .jpegData(compressionQuality: ImageProcessing.postJPEGQuality) {
            photoData = jpeg
            photoPreview = image.downsampled(maxDimension: 720)
        }
        removedPhoto = false
        photoError = nil
    }

    private func clearPhoto() {
        photoData = nil
        photoPreview = nil
        photoItem = nil
        photoError = nil
        removedPhoto = true
        existingMediaUrl = nil
        existingMediaType = nil
        messageFocused = true
    }

    private func prefillIfNeeded() {
        guard !didPrefill else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                messageFocused = true
            }
            return
        }
        didPrefill = true
        if let target = editingTarget {
            applyEditing(target)
        } else if let profile = initialRecipientProfile {
            selectLinkedRecipient(profile)
        } else if let initialRecipient {
            recipient = initialRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if editingTarget == nil,
           let initialMessage,
           !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = String(initialMessage.prefix(maxLength))
        }
        if editingTarget == nil,
           let fileName = initialImageFileName,
           let data = ComposeShareStore.readImageData(fileName: fileName),
           let image = UIImage(data: data) {
            applyCroppedPhoto(image)
            ComposeShareStore.removeImage(fileName: fileName)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            messageFocused = true
        }
    }

    /// Pull the member's email/phone from profiles so claim email can send
    /// without relying on the web API to fill recipient_email.
    private func loadLinkedRecipientContact(profileId: UUID) async {
        guard linkedRecipient?.id == profileId else { return }
        guard let contact = try? await GratitudeService.profileContact(id: profileId) else { return }
        if let email = contact.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            linkedRecipientEmail = AuthService.normalizedEmail(email)
        }
    }

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func beginEditing(_ gratitude: Gratitude) {
        sent = false
        activeEditing = gratitude
        didPrefill = true
        applyEditing(gratitude)
        messageBeforeAI = nil
        polishing = nil
        error = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            messageFocused = true
        }
    }

    private func applyEditing(_ editing: Gratitude) {
        message = editing.message
        visibility = editing.visibility ?? .public
        existingMediaUrl = editing.mediaUrl
        existingMediaType = editing.mediaType
        removedPhoto = false
        photoData = nil
        photoItem = nil
        photoPreview = nil
        linkedRecipient = nil
        linkedRecipientEmail = nil
        recipient = ""

        if let profile = editing.recipient {
            selectLinkedRecipient(profile)
        } else if let recipientId = editing.recipientId {
            Task {
                if let profile = try? await GratitudeService.profile(id: recipientId) {
                    selectLinkedRecipient(profile)
                } else {
                    applyEditingFreeText(editing)
                }
            }
        } else {
            applyEditingFreeText(editing)
        }

        if let url = editing.mediaURL {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    photoPreview = image.downsampled(maxDimension: 800)
                }
            }
        }
    }

    private func applyEditingFreeText(_ editing: Gratitude) {
        if let name = editing.recipientName, !name.isEmpty {
            recipient = name
        } else if let email = editing.recipientEmail {
            recipient = email
        } else if let phone = editing.recipientPhone {
            recipient = phone
        } else {
            recipient = ""
        }
    }

    // MARK: Send

    private func send() async {
        guard let userId = auth.userId, canSend else { return }
        sending = true
        error = nil
        do {
            await resolveRecipientBeforeSend()

            var mediaUrl: String?
            var mediaType: String?
            if let photoData {
                // Re-encode so uploads stay small even if photoData came from an older path.
                let uploadData: Data
                if let image = UIImage(data: photoData),
                   let compressed = ImageProcessing.jpegForUpload(image) {
                    uploadData = compressed
                } else {
                    uploadData = photoData
                }
                let url = try await GratitudeService.uploadMedia(
                    data: uploadData, contentType: "image/jpeg", userId: userId)
                mediaUrl = url.absoluteString
                mediaType = "image"
            } else if !removedPhoto {
                mediaUrl = existingMediaUrl ?? editingTarget?.mediaUrl
                mediaType = existingMediaType ?? editingTarget?.mediaType
            }

            let linked = linkedRecipient
            let contact: (name: String?, email: String?, phone: String?)
            if linked != nil {
                contact = (nil, nil, nil)
            } else {
                contact = parseRecipient(recipient)
                if let email = contact.email {
                    recipient = email
                } else {
                    recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if let editing = editingTarget {
                let updated = try await GratitudeService.update(
                    id: editing.id,
                    update: GratitudeUpdate(
                        message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                        recipientEmail: contact.email ?? linkedRecipientEmail ?? linked?.email,
                        recipientPhone: contact.phone ?? linked?.phone,
                        recipientName: contact.name ?? linked?.fullName ?? linked?.displayName,
                        visibility: visibility.rawValue,
                        mediaUrl: mediaUrl,
                        mediaType: mediaType
                    )
                )
                created = updated
                activeEditing = nil
                onSaved?(updated)
                if self.editing != nil {
                    dismiss()
                } else {
                    // Came from the success screen — show success again with the update.
                    sent = true
                }
            } else {
                let new = NewGratitude(
                    authorId: userId,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    recipientEmail: contact.email ?? linkedRecipientEmail ?? linked?.email,
                    recipientPhone: contact.phone ?? linked?.phone,
                    recipientName: contact.name ?? linked?.fullName ?? linked?.displayName,
                    recipientId: linked?.id,
                    visibility: visibility.rawValue,
                    mediaUrl: mediaUrl,
                    mediaType: mediaType,
                    source: "ios"
                )
                var result = try await GratitudeService.create(new)
                if result.recipient == nil, let linked {
                    result.recipient = linked
                }
                if isBlank(result.recipientName), let linked {
                    result.recipientName = linked.fullName ?? linked.displayName
                }
                if isBlank(result.recipientEmail) {
                    result.recipientEmail = linkedRecipientEmail ?? linked?.email
                }
                created = result
                sent = true
                await refreshWidgetAfterSend()
            }
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }

    private func refreshWidgetAfterSend() async {
        guard let userId = auth.userId else { return }
        await WidgetSnapshotRefresher.refresh(
            displayName: auth.currentProfile?.displayName,
            userId: userId,
            email: auth.currentProfile?.email,
            phone: auth.currentProfile?.phone
        )
    }

    /// Link a selected/@username member and finish loading their email before create.
    private func resolveRecipientBeforeSend() async {
        if linkedRecipient == nil {
            let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("@") {
                let handle = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !handle.isEmpty,
                   let profile = try? await GratitudeService.profile(username: handle) {
                    selectLinkedRecipient(profile)
                }
            }
        }

        if let linked = linkedRecipient, isBlank(linkedRecipientEmail) {
            await loadLinkedRecipientContact(profileId: linked.id)
        }
    }

    private func parseRecipient(_ raw: String)
        -> (name: String?, email: String?, phone: String?) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil, nil) }
        if looksLikeEmail(value) {
            return (nil, AuthService.normalizedEmail(value), nil)
        }
        // Bare @username is handled via profile lookup before send — treat as name if unresolved.
        if value.hasPrefix("@") {
            let handle = String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return (handle.isEmpty ? nil : handle, nil, nil)
        }
        let digits = value.filter { $0.isNumber }
        if digits.count >= 7 && value.allSatisfy({ "+()- 0123456789".contains($0) }) {
            let e164 = value.hasPrefix("+") ? "+" + digits : "+1" + digits
            return (nil, nil, e164)
        }
        return (value, nil, nil)
    }

    private func looksLikeEmail(_ value: String) -> Bool {
        guard let at = value.firstIndex(of: "@") else { return false }
        let local = value[..<at]
        let domain = value[value.index(after: at)...]
        return !local.isEmpty
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
            && !domain.contains("@")
    }

    private func reset() {
        recipient = ""
        message = ""
        photoData = nil
        photoPreview = nil
        photoItem = nil
        cropItem = nil
        photoError = nil
        visibility = .public
        sent = false
        created = nil
        activeEditing = nil
        polishing = nil
        messageBeforeAI = nil
        existingMediaUrl = nil
        existingMediaType = nil
        removedPhoto = false
        linkedRecipient = nil
        linkedRecipientEmail = nil
        recipientResults = []
        recipientSearching = false
        recipientDidSearch = false
        didPrefill = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            messageFocused = true
        }
    }
}

// Subtle press feedback for chips / emoji buttons.
private struct ScalePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SuccessView: View {
    let gratitude: Gratitude
    var onEdit: () -> Void
    var onDone: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var shareURL: URL {
        gratitude.claimURL ?? gratitude.webURL
    }

    private var recipientEmail: String? {
        let value = gratitude.recipientEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// Shown on share rows — prefer @username / name; blank To is fine.
    private var emailToLabel: String {
        if let username = gratitude.recipient?.username.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return "To @\(username)"
        }
        if let name = gratitude.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "To \(name)"
        }
        if let display = gratitude.recipient?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !display.isEmpty {
            return "To \(display)"
        }
        if recipientEmail != nil {
            return "To their email"
        }
        return "Choose an address"
    }

    private var shareMessage: String {
        let name = gratitude.recipientName?.split(separator: " ").first.map(String.init)
            ?? gratitude.recipient?.fullName?.split(separator: " ").first.map(String.init)
        let greeting = name.map { "Hey \($0)! " } ?? "Hey! "
        return greeting
            + "I wrote you an appreciation on OpenThanks 💛 You can read and claim it here: "
            + shareURL.absoluteString
    }

    private var subtitle: String {
        if gratitude.recipientId != nil || recipientEmail != nil {
            return "We emailed them the claim link when we could. You can also share it yourself, or edit anything before they claim."
        }
        return "Send the claim link so they can open it — or edit anything before they do."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    AppreciationMoment(size: 88)
                        .padding(.top, 28)

                    VStack(spacing: 8) {
                        Text("Your appreciation\nhas been shared!")
                            .font(Theme.display(28, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .softNoteReveal(delay: 0.12)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = shareURL.absoluteString
                        withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copied ? "checkmark" : "link")
                                .font(.system(size: 15, weight: .bold))
                            Text(copied ? "Link Copied!" : "Copy Link")
                        }
                    }
                    .buttonStyle(CTAButtonStyle())
                    .sensoryFeedback(.success, trigger: copied)

                    ShareActionRow(
                        title: "Send via Text",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        subtitle: gratitude.recipientPhone.map { "To \($0)" }
                    ) {
                        openSMS()
                    }

                    ShareActionRow(
                        title: "Send via WhatsApp",
                        systemImage: "phone.bubble.fill",
                        subtitle: gratitude.recipientPhone.map { "To \($0)" }
                            ?? "Share the claim link"
                    ) {
                        openWhatsApp()
                    }

                    ShareActionRow(
                        title: "Send via Email",
                        systemImage: "envelope.fill",
                        subtitle: emailToLabel
                    ) {
                        openMail()
                    }

                    ShareActionRow(
                        title: "Edit Appreciation",
                        systemImage: "square.and.pencil",
                        subtitle: "Update the message or details"
                    ) {
                        onEdit()
                    }
                }
                .padding(.horizontal, 20)

                Button(action: onDone) {
                    Text("Done")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func openSMS() {
        var components = URLComponents()
        components.scheme = "sms"
        if let phone = gratitude.recipientPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty {
            components.path = phone
        }
        components.queryItems = [URLQueryItem(name: "body", value: shareMessage)]
        if let url = components.url {
            openURL(url)
        }
    }

    private func openMail() {
        // Blank To is intentional when we only know the username — Mail lets
        // the sender pick an address while keeping subject/body filled in.
        var components = URLComponents()
        components.scheme = "mailto"
        if let email = recipientEmail {
            components.path = email
        }
        components.queryItems = [
            URLQueryItem(name: "subject", value: "I wrote you an appreciation on OpenThanks"),
            URLQueryItem(name: "body", value: shareMessage),
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private func openWhatsApp() {
        if let url = ShareChannels.whatsAppURL(
            message: shareMessage,
            phone: gratitude.recipientPhone
        ) {
            openURL(url)
        }
    }
}
