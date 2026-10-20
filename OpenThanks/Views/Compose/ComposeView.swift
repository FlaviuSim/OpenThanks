import SwiftUI
import PhotosUI
import AVKit

struct ComposeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(UserBlockService.self) private var userBlocks
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// When set, the form edits this pending appreciation instead of creating one.
    var editing: Gratitude? = nil
    /// Prefills the recipient field (e.g. from Home people search invite).
    var initialRecipient: String? = nil
    /// Prefills and links an existing member (e.g. Thank from their profile).
    var initialRecipientProfile: Profile? = nil
    /// Prefills the message (e.g. Siri “thank … for …”).
    var initialMessage: String? = nil
    /// Empty-field hint when opened from a prompt notification (Friday, etc.).
    var initialMessagePlaceholder: String? = nil
    /// App Group image from the Share Extension.
    var initialImageFileName: String? = nil
    /// Parent appreciation for pay-it-forward / ripple attribution.
    var inspiredByGratitudeId: UUID? = nil
    /// Display name used when building an inspired-by placeholder.
    var inspiredByAuthorName: String? = nil
    /// PostHog `source` for the compose funnel (matches web event names).
    var analyticsSource: String = "compose"
    /// Shown above the message field. Never copied into the message.
    var campaignHint: String? = nil
    /// PostHog `campaign` when compose was opened from a daily prompt.
    var campaignId: String? = nil
    var campaignDay: Int? = nil
    /// Watch voice drafts can save without choosing a recipient yet.
    var allowsEmptyRecipient: Bool = false
    /// Open straight on the share screen (author opening their own pending note).
    var opensOnShareScreen: Bool = false
    /// Skip the inner NavigationStack when a parent stack already exists.
    var useParentNavigation: Bool = false
    var onSaved: ((Gratitude) -> Void)? = nil

    init(
        editing: Gratitude? = nil,
        initialRecipient: String? = nil,
        initialRecipientProfile: Profile? = nil,
        initialMessage: String? = nil,
        initialMessagePlaceholder: String? = nil,
        initialImageFileName: String? = nil,
        inspiredByGratitudeId: UUID? = nil,
        inspiredByAuthorName: String? = nil,
        campaignHint: String? = nil,
        campaignId: String? = nil,
        campaignDay: Int? = nil,
        analyticsSource: String = "compose",
        allowsEmptyRecipient: Bool = false,
        opensOnShareScreen: Bool = false,
        useParentNavigation: Bool = false,
        onSaved: ((Gratitude) -> Void)? = nil
    ) {
        self.editing = editing
        self.initialRecipient = initialRecipient
        self.initialRecipientProfile = initialRecipientProfile
        self.initialMessage = initialMessage
        self.initialMessagePlaceholder = initialMessagePlaceholder
        self.initialImageFileName = initialImageFileName
        self.inspiredByGratitudeId = inspiredByGratitudeId
        self.inspiredByAuthorName = inspiredByAuthorName
        self.campaignHint = campaignHint
        self.campaignId = campaignId
        self.campaignDay = campaignDay
        self.analyticsSource = analyticsSource
        // Match ComposeLaunchBridge: any launch without a prefilled recipient uses
        // write → deliver, so Home “Thank Someone” and similar CTAs never land on
        // the classic one-screen form by accident.
        self.allowsEmptyRecipient = ComposeLaunchBridge.Request.resolveAllowsEmptyRecipient(
            explicit: allowsEmptyRecipient,
            recipientName: initialRecipient,
            profile: initialRecipientProfile,
            editingGratitude: editing,
            analyticsSource: analyticsSource
        )
        self.opensOnShareScreen = opensOnShareScreen
        self.useParentNavigation = useParentNavigation
        self.onSaved = onSaved
        if opensOnShareScreen, let editing {
            _sent = State(initialValue: true)
            _created = State(initialValue: editing)
            _didPrefill = State(initialValue: true)
        }
    }

    @State private var recipient = ""
    @State private var message = ""
    @State private var visibility: GratitudeVisibility = .public
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotosPicker = false
    @State private var photoData: Data?
    @State private var mediaContentType: String?
    @State private var attachedMediaKind: AttachedMediaKind?
    @State private var photoPreview: UIImage?
    /// Full-resolution (or editing-sized) image so crop/zoom can be reopened after attach.
    @State private var editableSourceImage: UIImage?
    @State private var videoPreviewURL: URL?
    @State private var videoPreviewIsLocalTemp = false
    @State private var showFullScreenVideo = false
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
    /// True only after a fresh create — not when returning to Success after Edit.
    @State private var offerEnjoymentPrompt = false
    /// Edit target after a successful send (or the incoming `editing` value).
    @State private var activeEditing: Gratitude?
    @State private var polishing: AppreciationAI.Style?
    @State private var messageBeforeAI: String?
    /// Queued chip insert for `MessageEditor` (places caret after the emoji).
    @State private var pendingMessageInsert: MessageEditor.PendingInsert?
    @StateObject private var dictation = AppreciationDictation()
    @State private var didPrefill = false
    @State private var didTrackFormStart = false
    @State private var didCompleteSend = false
    /// One id for every PostHog event from this open of the form.
    @State private var formSessionId = UUID().uuidString.lowercased()
    @State private var formOpenedAt = Date()
    @State private var priorErrorCount = 0
    /// True after a send failure so the draft stays and Retry is offered.
    @State private var sendFailed = false
    /// Cancel from the share screen's Edit returns to share without an abandon event.
    @State private var suppressAbandonTracking = false
    /// Kept so create can set `recipient_id` even if the typed field is a name.
    @State private var linkedRecipient: Profile?
    /// Email for the linked member — loaded eagerly so claim mail can send
    /// even when the profile object passed into compose has no email.
    @State private var linkedRecipientEmail: String?
    /// User removed the member chip. Distinct from “profile embed still loading”.
    @State private var didClearRecipient = false
    @State private var recipientResults: [Profile] = []
    @State private var recipientSearching = false
    /// True after the debounced search for the current query completes (including empty).
    @State private var recipientSearchFinished = false
    /// User confirmed a free-text name/email as a non-member recipient chip.
    @State private var guestRecipientConfirmed = false
    @FocusState private var messageFocused: Bool
    @FocusState private var recipientFocused: Bool
    @State private var showAddLinkSheet = false
    @State private var linkLabelDraft = ""
    @State private var linkURLDraft = ""
    @State private var linkReplaceRange = NSRange(location: 0, length: 0)
    @State private var addingLink = false
    @State private var linkError: String?
    /// Cached so opening compose doesn’t hit Foundation Models on every body pass.
    @State private var aiAvailable = false
    /// Name required before save so feed cards never show a blank author.
    @State private var showDisplayNameSheet = false

    private let maxLength = 1500

    private var needsDisplayName: Bool {
        auth.currentProfile?.needsDisplayName == true
    }
    private let quickEmojis = ["🙏", "❤️", "🫶", "🥰", "🤗", "✨"]

    private var campaignHintText: String? {
        let trimmed = campaignHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var messagePlaceholderText: String {
        if campaignHintText != nil { return "Thank you for..." }
        let custom = initialMessagePlaceholder?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        if inspiredByGratitudeId != nil {
            let raw = inspiredByAuthorName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = (raw?.isEmpty == false)
                ? (raw!.split(separator: " ").first.map(String.init) ?? raw!)
                : "someone"
            return "Thank someone who deserves it — inspired by \(first)’s appreciation for you."
        }
        return "Thank you for..."
    }

    private var editingTarget: Gratitude? { activeEditing ?? editing }
    private var isEditing: Bool { editingTarget != nil }
    /// Watch / pending row that still has nobody to notify.
    private var isFirstDelivery: Bool { editingTarget?.hasNoRecipient == true }

    /// Two-step write → deliver when no recipient was prefilled (`allowsEmptyRecipient`).
    private var usesTwoStepFlow: Bool { allowsEmptyRecipient }

    private var toolbarSaveTitle: String {
        if usesTwoStepFlow {
            return isEditing ? "Continue" : "Continue"
        }
        if isEditing {
            if isFirstDelivery { return hasRecipient ? "Save" : "Save to Pending" }
            return "Save Changes"
        }
        return "Save"
    }

    private var primarySaveTitle: String {
        if usesTwoStepFlow {
            return "Continue"
        }
        if isEditing {
            if isFirstDelivery { return hasRecipient ? "Save" : "Save to Pending" }
            return "Save Changes"
        }
        return "Save Appreciation"
    }

    private enum AttachedMediaKind {
        case image
        case video
    }

    private struct CropItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var hasAttachedMedia: Bool {
        if photoData != nil { return true }
        if photoPreview != nil || videoPreviewURL != nil { return true }
        return existingMediaUrl != nil && !removedPhoto
    }

    private var showingVideo: Bool {
        if attachedMediaKind == .video { return true }
        if attachedMediaKind == .image { return false }
        return existingMediaType?.lowercased().hasPrefix("video") == true && !removedPhoto
    }

    var body: some View {
        composeContainer
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
                    applyCroppedPhoto(cropped, source: item.image)
                    cropItem = nil
                    photoItem = nil
                    messageFocused = true
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFullScreenVideo) {
            if let url = videoPreviewURL ?? existingMediaURLResolved {
                FullScreenVideoView(url: url)
            }
        }
    }

    @ViewBuilder
    private var composeContainer: some View {
        if useParentNavigation {
            composeRoot
        } else {
            NavigationStack { composeRoot }
        }
    }

    @ViewBuilder
    private var composeRoot: some View {
        if sent, let created, activeEditing == nil {
            if usesTwoStepFlow {
                DeliverAppreciationView(
                    gratitude: Binding(
                        get: { self.created ?? created },
                        set: { self.created = $0 }
                    ),
                    preferredEmail: auth.currentProfile?.email,
                    preferredName: auth.currentProfile?.fullName ?? auth.currentProfile?.displayName,
                    offerEnjoymentPrompt: offerEnjoymentPrompt,
                    onEdit: { beginEditing(self.created ?? created) },
                    onDone: { finishPostSaveFlow() },
                    onUpdated: { updated in onSaved?(updated) }
                )
                .id(shareScreenIdentity(self.created ?? created))
            } else {
                SuccessView(
                    gratitude: created,
                    preferredEmail: auth.currentProfile?.email,
                    preferredName: auth.currentProfile?.fullName ?? auth.currentProfile?.displayName,
                    offerEnjoymentPrompt: offerEnjoymentPrompt,
                    onEdit: { beginEditing(created) },
                    onDone: { finishPostSaveFlow() }
                )
                .id(shareScreenIdentity(created))
            }
        } else {
            form
        }
    }

    /// Dismiss compose, then offer deferred permission prompts from main.
    private func finishPostSaveFlow() {
        dismiss()
        // Defer so compose cover can dismiss before the permission sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PermissionPromptScheduler.shared.scheduleAfterAppreciation(source: "post_send")
        }
    }

    /// New identity after edit/save so the share screen can't keep the pre-edit note.
    /// Recipient fields are omitted — changing Send-to must not remount Deliver.
    private func shareScreenIdentity(_ gratitude: Gratitude) -> String {
        ShareScreenIdentity.make(
            id: gratitude.id,
            message: gratitude.message,
            mediaUrl: gratitude.mediaUrl
        )
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if usesTwoStepFlow && analyticsSource == "watch" {
                    watchDraftBanner
                } else if usesTwoStepFlow && !isEditing {
                    twoStepWriteBanner
                }

                if isEditing {
                    intro
                }

                if !usesTwoStepFlow {
                    recipientSection
                }

                messageSection

                photoSection

                if !usesTwoStepFlow {
                    visibilitySection
                }

                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(Theme.body(13))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if sendFailed {
                            Button("Retry") {
                                messageFocused = false
                                recipientFocused = false
                                Task { await send() }
                            }
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                            .disabled(sending)
                            .accessibilityLabel("Retry sending this appreciation")
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // CTA lives in scroll content so it isn’t pinned above the keyboard
                // (which left a large empty band mid-screen while editing).
                if let saveBlockedReason, !sending {
                    Text(saveBlockedReason)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                sendBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollDismissesKeyboard(.interactively)
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .sheet(isPresented: $showDisplayNameSheet) {
            DisplayNameSheet(formSessionId: formSessionId)
                .presentationDetents([.medium])
                .syncAppAppearance()
        }
        .background(Theme.background)
        .navigationTitle(isEditing ? "Edit Appreciation" : "New Appreciation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: cancelCompose)
                    .font(Theme.body(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if sending {
                    ProgressView()
                        .controlSize(.small)
                } else if needsDisplayName {
                    Button("Add name") {
                        messageFocused = false
                        recipientFocused = false
                        showDisplayNameSheet = true
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .accessibilityHint("Add your name before saving")
                } else {
                    Button(toolbarSaveTitle) {
                        messageFocused = false
                        recipientFocused = false
                        Task { await send() }
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(canSend ? Theme.coral : Theme.textTertiary)
                    .opacity(canSend ? 1 : 0.45)
                    .disabled(!canSend)
                    .accessibilityHint(saveBlockedReason ?? "Saves this appreciation")
                }
            }
            // MessageEditor already owns Done on its accessory — only show this
            // when the recipient field (SwiftUI TextField) is focused.
            if !messageFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        messageFocused = false
                        recipientFocused = false
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            prefillIfNeeded()
            trackFormStartIfNeeded()
            dictation.refreshAvailability()
            // Don’t block presenting compose on Foundation Models readiness.
            Task.detached(priority: .utility) {
                let available = AppreciationAI.isAvailable
                await MainActor.run { aiAvailable = available }
            }
        }
        .onDisappear {
            Task { await dictation.finishListening() }
            let completedSend = didCompleteSend || sent
            trackAbandonIfNeeded()
            guard ownsUnsentDraft, !completedSend else { return }
            let keptRecipient = recipient
            let keptMessage = message
            Task {
                let effect = await ComposeDraftStore.leave(
                    recipient: keptRecipient,
                    message: keptMessage
                )
                if effect.saved {
                    Analytics.captureDraftEvent("draft_saved", hasRecipient: effect.hasRecipient)
                }
                if effect.scheduled {
                    Analytics.captureDraftEvent(
                        "draft_reminder_scheduled",
                        hasRecipient: effect.hasRecipient
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                dictation.handleAppDidBecomeActive()
            case .background:
                dictation.handleAppWillResignActive()
            default:
                break
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            trackFormStartIfNeeded()
            Task { await handlePickedMedia(item) }
        }
        .onChange(of: message) { _, _ in
            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                trackFormStartIfNeeded()
            }
        }
        .onChange(of: recipient) { _, _ in
            if !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                trackFormStartIfNeeded()
            }
        }
        .onChange(of: dictation.transcript) { _, _ in
            applyDictationTranscript()
        }
        .onChange(of: dictation.textEpoch) { _, _ in
            applyDictationTranscript()
        }
        .onChange(of: dictation.isListening) { wasListening, listening in
            if !listening {
                applyDictationTranscript()
                if wasListening, dictation.lastUtteranceLength > 0 {
                    Analytics.appreciationVoiceDictation(
                        messageLength: dictation.lastUtteranceLength,
                        formSessionId: formSessionId
                    )
                }
            }
        }
        .onChange(of: dictation.errorMessage) { _, err in
            if let err, !err.isEmpty {
                error = err
                sendFailed = false
            }
        }
    }

    private func trackFormStartIfNeeded() {
        guard !didTrackFormStart else { return }
        didTrackFormStart = true
        Analytics.appreciationFormStarted(source: analyticsSource, formSessionId: formSessionId)
    }

    private func trackAbandonIfNeeded() {
        if suppressAbandonTracking {
            suppressAbandonTracking = false
            return
        }
        guard didTrackFormStart, !didCompleteSend, !sent else { return }
        didCompleteSend = true // prevent double-fire from Cancel + onDisappear
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientKind = recipientTypeForAnalytics()
        Analytics.appreciationFormAbandoned(
            source: analyticsSource,
            messageLength: trimmed.count,
            hasRecipient: recipientKind != "none",
            toMember: recipientKind == "member",
            recipientType: recipientKind,
            hasMedia: hasAttachedMedia,
            lastStep: abandonLastStep,
            secondsOpen: formSecondsOpen,
            priorErrorCount: priorErrorCount,
            autopresented: formWasAutopresented,
            formSessionId: formSessionId
        )
        // Watch: dismiss = keep Pending on server, stop auto-opening compose.
        if analyticsSource == "watch" {
            let authorId = auth.userId
            Task { @MainActor in
                await WatchVoiceDraftStore.finishReviewSession(authorId: authorId)
            }
        }
    }

    /// Blank post-login compose is opened for the user. Everything else is a tap.
    private var formWasAutopresented: Bool {
        analyticsSource == "app_open" || analyticsSource == "post_login"
    }

    private var formSecondsOpen: Int {
        max(0, Int(Date().timeIntervalSince(formOpenedAt)))
    }

    /// Furthest step still on screen when the form closes without a send.
    private var abandonLastStep: String {
        if priorErrorCount > 0 { return "send" }
        if hasAttachedMedia { return "photo" }
        if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "message" }
        if hasRecipient { return "recipient" }
        return "compose"
    }

    /// member | email | phone | name | none — shared by submit + abandon analytics.
    private func recipientTypeForAnalytics() -> String {
        if linkedRecipient != nil { return "member" }
        let parsed = parseRecipient(recipient)
        if parsed.email != nil { return "email" }
        if parsed.phone != nil { return "phone" }
        if parsed.name != nil { return "name" }
        return "none"
    }

    private var existingMediaURLResolved: URL? {
        guard !removedPhoto else { return nil }
        return AppConfig.mediaURL(from: existingMediaUrl)
    }

    // MARK: Sections

    private var intro: some View {
        Text("Edit your appreciation")
            .font(Theme.display(26, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var watchDraftBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("From your Watch")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Polish your note, then Continue to choose who it’s for and share the link — or Cancel and finish later from Pending.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.coral.opacity(0.22), lineWidth: 1)
        )
    }

    private var twoStepWriteBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Write your appreciation")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add your message and an optional photo. Next you’ll choose who to send it to.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.coral.opacity(0.22), lineWidth: 1)
        )
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recipient")
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                recipientFieldChrome

                if linkedRecipient == nil, !guestRecipientConfirmed, showRecipientSuggestions {
                    recipientSuggestions
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showRecipientSuggestions)
            .animation(.easeInOut(duration: 0.18), value: linkedRecipient?.id)
            .animation(.easeInOut(duration: 0.18), value: guestRecipientConfirmed)
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
            } else if guestRecipientConfirmed {
                HStack(spacing: 10) {
                    guestRecipientChip
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                TextField("Name or Email", text: $recipient)
                    .textInputAutocapitalization(recipient.contains("@") ? .never : .words)
                    .autocorrectionDisabled()
                    .keyboardType(recipient.contains("@") ? .emailAddress : .default)
                    .textContentType(recipient.contains("@") ? .emailAddress : .name)
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
                    recipientFocused && linkedRecipient == nil && !guestRecipientConfirmed
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

    private var guestRecipientChip: some View {
        let label = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmail = looksLikeEmail(label)
        return HStack(spacing: 8) {
            Image(systemName: isEmail ? "envelope.fill" : "person.crop.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .frame(width: 28, height: 28)
            Text(label)
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Button {
                clearGuestRecipient(focusField: true)
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
        .accessibilityLabel("Recipient \(label)")
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
            } else {
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

                    if index < recipientResults.count - 1 || shouldShowAddGuestRow {
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 0.5)
                            .padding(.leading, 66)
                    }
                }

                if shouldShowAddGuestRow {
                    addGuestRecipientRow
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
    }

    private var addGuestRecipientRow: some View {
        let query = recipientSearchQuery
        let isEmail = looksLikeEmail(query)
        let title = isEmail ? "Add \(query)" : "Add “\(query)”"
        return Button {
            confirmGuestRecipient()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isEmail ? "envelope" : "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("We’ll share a link after you save")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
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
        .accessibilityLabel(title)
        .accessibilityHint("Adds this person as the recipient. You can share a link after saving.")
    }

    private var recipientSearchQuery: String {
        guard linkedRecipient == nil, !guestRecipientConfirmed else { return "" }
        return recipient.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showRecipientSuggestions: Bool {
        linkedRecipient == nil
            && !guestRecipientConfirmed
            && recipientFocused
            && recipientSearchQuery.count >= 2
            && (recipientSearching || recipientSearchFinished)
    }

    private var shouldShowAddGuestRow: Bool {
        recipientSearchFinished
            && !recipientSearching
            && recipientSearchQuery.count >= 2
            && !hasExactMemberMatch(for: recipientSearchQuery)
    }

    private func hasExactMemberMatch(for rawQuery: String) -> Bool {
        let query = rawQuery.hasPrefix("@") ? String(rawQuery.dropFirst()) : rawQuery
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        return recipientResults.contains { profile in
            let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !username.isEmpty, username == needle { return true }
            let display = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !display.isEmpty, display == needle { return true }
            if let full = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !full.isEmpty, full == needle {
                return true
            }
            if let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !email.isEmpty, email == needle {
                return true
            }
            return false
        }
    }

    private func chipLabel(for profile: Profile) -> String {
        let handle = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !handle.isEmpty { return "@\(handle)" }
        return profile.displayName
    }

    private func selectLinkedRecipient(_ profile: Profile) {
        didClearRecipient = false
        guestRecipientConfirmed = false
        linkedRecipient = profile
        recipient = ""
        recipientResults = []
        recipientSearching = false
        recipientSearchFinished = false
        recipientFocused = false
        if let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            linkedRecipientEmail = AuthService.normalizedEmail(email)
        } else {
            linkedRecipientEmail = nil
        }
        Task { await loadLinkedRecipientContact(profileId: profile.id) }
    }

    private func confirmGuestRecipient() {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        didClearRecipient = false
        guestRecipientConfirmed = true
        recipient = trimmed
        recipientResults = []
        recipientSearching = false
        recipientSearchFinished = false
        recipientFocused = false
        Analytics.capture("compose_guest_recipient_added", [
            "recipient_kind": looksLikeEmail(trimmed) ? "email" : "name",
            "form_session_id": formSessionId,
        ])
    }

    private func clearGuestRecipient(focusField: Bool) {
        guestRecipientConfirmed = false
        recipientSearchFinished = false
        recipientResults = []
        if focusField {
            recipientFocused = true
        }
    }

    private func clearLinkedRecipient(focusField: Bool) {
        didClearRecipient = true
        linkedRecipient = nil
        linkedRecipientEmail = nil
        guestRecipientConfirmed = false
        recipient = ""
        recipientResults = []
        recipientSearching = false
        recipientSearchFinished = false
        if focusField {
            recipientFocused = true
        }
    }

    private func runRecipientSearch(for current: String) async {
        guard linkedRecipient == nil, !guestRecipientConfirmed, current.count >= 2 else {
            recipientResults = []
            recipientSearching = false
            recipientSearchFinished = false
            return
        }

        recipientSearching = true
        recipientSearchFinished = false
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        let query = current.hasPrefix("@") ? String(current.dropFirst()) : current
        guard query.count >= 2 else {
            recipientResults = []
            recipientSearching = false
            recipientSearchFinished = false
            return
        }

        do {
            let found = try await GratitudeService.searchProfiles(query: query)
            guard !Task.isCancelled else { return }
            let selfId = auth.userId
            recipientResults = userBlocks.filterProfiles(found).filter { $0.id != selfId }
        } catch {
            if !error.isCancellation {
                recipientResults = []
            }
        }
        recipientSearching = false
        recipientSearchFinished = true
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let campaignHintText {
                VStack(alignment: .leading, spacing: 4) {
                    Text(campaignDay.map { "\(CampaignFeed.cardTitle) · Day \($0)" } ?? CampaignFeed.cardTitle)
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                    Text(campaignHintText)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.coral.opacity(0.10))
                )
                .accessibilityElement(children: .combine)
            }
            messageField
        }
    }

    private var messageField: some View {
        field(label: "Your Appreciation") {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    MessageEditor(
                        text: $message,
                        minHeight: 160,
                        isEditable: !(loadingPhoto || sending || polishing != nil || dictation.isListening || dictation.isStopping),
                        onAddLink: { label, range in
                            beginAddLink(label: label, range: range)
                        },
                        showAI: aiAvailable,
                        aiBusy: polishing != nil,
                        aiEnabled: polishing == nil
                            && !sending
                            && !dictation.isListening
                            && !dictation.isTransitioning
                            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onAI: aiAvailable
                            ? { style in Task { await runAI(style) } }
                            : nil,
                        showVoice: true,
                        voiceListening: dictation.isListening,
                        voiceBusy: dictation.isTransitioning,
                        voiceEnabled: voiceControlsEnabled,
                        onToggleVoice: { Task { await toggleVoiceDictation() } },
                        quickEmojis: quickEmojis,
                        onInsertEmoji: { insertEmoji($0) },
                        onFocusChange: { focused in
                            messageFocused = focused
                            if focused { recipientFocused = false }
                        },
                        pendingInsert: pendingMessageInsert,
                        onPendingInsertConsumed: { id in
                            if pendingMessageInsert?.id == id {
                                pendingMessageInsert = nil
                            }
                            if message.count > maxLength {
                                message = String(message.prefix(maxLength))
                            }
                        }
                    )
                    .frame(minHeight: 160)

                    if message.isEmpty {
                        Text(messagePlaceholderText)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.textTertiary)
                            // Match MessageEditor.textInsets so caret/glyphs line up.
                            .padding(.top, 12)
                            .padding(.leading, 12)
                            .padding(.trailing, 72)
                            .allowsHitTesting(false)
                            .accessibilityLabel(messagePlaceholderText)
                    }

                    voiceOverlayButton
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                if dictation.isStarting {
                    Text("Starting microphone…")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                } else if dictation.isStopping {
                    Text("Finishing up…")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                } else if dictation.isListening {
                    Text("Pauses are fine — tap Listening to stop.")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }

                Divider().overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: 12) {
                    // When the message field is focused, emojis live on the opaque
                    // keyboard accessory (so they aren’t trapped under a translucent bar).
                    if !messageFocused {
                        emojiShortcuts
                    }

                    if aiAvailable {
                        aiChips
                    }

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
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showAddLinkSheet) {
            addLinkSheet
        }
    }

    private var addLinkSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link text", text: $linkLabelDraft)
                        .textInputAutocapitalization(.sentences)
                    TextField("https://", text: $linkURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .onChange(of: linkURLDraft) { _, _ in
                            linkError = nil
                        }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Highlight text in your message, then Add link — or enter both the label and URL here. Links stay as plain text and open when someone reads the appreciation.")
                            .font(Theme.body(12))
                        if let linkError {
                            Text(linkError)
                                .font(Theme.body(13))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddLinkSheet = false }
                        .foregroundStyle(Theme.coral)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyLink()
                    } label: {
                        if addingLink {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Add")
                        }
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .disabled(!canAttemptLink || addingLink)
                    .accessibilityLabel(addingLink ? "Adding link" : "Add")
                }
            }
            .syncAppAppearance()
        }
        // Medium alone clips fields + Add under the iPad keyboard; allow large.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var canAttemptLink: Bool {
        !linkLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !linkURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginAddLink(label: String, range: NSRange) {
        linkLabelDraft = label
        linkURLDraft = ""
        linkReplaceRange = range
        linkError = nil
        addingLink = false
        showAddLinkSheet = true
        messageFocused = false
    }

    private func applyLink() {
        guard !addingLink else { return }
        guard let markdown = LinkifiedText.markdownLink(label: linkLabelDraft, urlRaw: linkURLDraft) else {
            linkError = "That address doesn't look valid. Try example.com."
            return
        }
        addingLink = true
        linkError = nil
        let ns = message as NSString
        let maxLoc = ns.length
        let location = min(max(linkReplaceRange.location, 0), maxLoc)
        let length = min(max(linkReplaceRange.length, 0), maxLoc - location)
        let range = NSRange(location: location, length: length)
        var next = ns.replacingCharacters(in: range, with: markdown)
        if next.count > maxLength {
            next = String(next.prefix(maxLength))
        }
        guard next.contains(markdown) else {
            addingLink = false
            linkError = "Couldn't add that link. Shorten the message and try again."
            return
        }
        message = next
        // Let the message editor take the new text before the sheet goes away,
        // so the link is already in the note when Add closes.
        Task { @MainActor in
            await Task.yield()
            guard message.contains(markdown) else {
                addingLink = false
                linkError = "Couldn't add that link. Try again."
                return
            }
            showAddLinkSheet = false
            addingLink = false
            messageFocused = true
        }
    }

    private var photoSection: some View {
        field(label: nil, hint: nil) {
            if hasAttachedMedia {
                ZStack(alignment: .topTrailing) {
                    mediaPreviewBody

                    HStack(spacing: 8) {
                        if !showingVideo {
                            Button {
                                openCropEditor()
                            } label: {
                                Label("Adjust", systemImage: "crop")
                                    .font(Theme.body(12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(.black.opacity(0.55), in: Capsule())
                            }
                            .disabled(loadingPhoto || sending)
                            .accessibilityLabel("Adjust photo crop")
                        }

                        Button(action: openPhotosPicker) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
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
                        .accessibilityLabel("Remove media")
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button(action: openPhotosPicker) {
                    HStack(spacing: 14) {
                        ZStack {
                            if loadingPhoto {
                                Circle()
                                    .fill(Theme.coral)
                                    .frame(width: 46, height: 46)
                                ProgressView().tint(.white)
                            } else {
                                ActionGlyph(systemImage: "photo.on.rectangle.angled")
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(loadingPhoto ? "Preparing…" : "Add a photo or video (optional)")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if loadingPhoto {
                                Text("Hang tight")
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
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

    @ViewBuilder
    private var mediaPreviewBody: some View {
        if showingVideo, let _ = videoPreviewURL ?? existingMediaURLResolved {
            Button {
                showFullScreenVideo = true
            } label: {
                ZStack(alignment: .bottomLeading) {
                    if let photoPreview {
                        Image(uiImage: photoPreview)
                            .resizable()
                            .flexiblePhotoPreview(maxHeight: 240)
                            .overlay { Color.black.opacity(0.22) }
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.surfaceRaised)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                    }
                    Label("Video · tap to play", systemImage: "play.circle.fill")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview video, tap to open")
        } else if let photoPreview {
            Button {
                openCropEditor()
            } label: {
                Image(uiImage: photoPreview)
                    .resizable()
                    .flexiblePhotoPreview(maxHeight: 240)
                    .overlay(alignment: .bottomLeading) {
                        Label("Tap to adjust", systemImage: "crop")
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(12)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attached photo, tap to adjust crop")
        } else if let url = existingMediaURLResolved {
            // Remote image still loading into preview — show placeholder.
            CachedAsyncImage(url: url, maxPixelSize: RemoteImageCache.feedMaxPixelSize) { image in
                image
                    .resizable()
                    .flexiblePhotoPreview(maxHeight: 240)
            } placeholder: {
                ProgressView().tint(Theme.coral)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(Theme.surfaceRaised)
            }
        }
    }

    /// Authors may change public/private until the recipient accepts.
    private var canEditVisibility: Bool {
        guard let editing = editingTarget else { return true }
        return editing.status == .pending || editing.status == nil
    }

    private var visibilitySection: some View {
        Button {
            guard canEditVisibility else { return }
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
                    Text(
                        canEditVisibility
                            ? (visibility == .public
                                ? "In the feed once they accept"
                                : "Only you and the recipient can see")
                            : (visibility == .public
                                ? "Visible in the community feed"
                                : "Locked after accept — only you and the recipient")
                    )
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if canEditVisibility {
                    Text("Switch")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(sending || !canEditVisibility)
        .accessibilityHint(canEditVisibility
            ? "Switches between public and private"
            : "Visibility is locked after the appreciation is accepted")
        .sensoryFeedback(.selection, trigger: visibility)
    }

    private var sendBar: some View {
        Button {
            messageFocused = false
            recipientFocused = false
            if needsDisplayName {
                showDisplayNameSheet = true
            } else {
                Task { await send() }
            }
        } label: {
            HStack(spacing: 8) {
                if sending {
                    ProgressView()
                        .tint(Color(hex: 0x2B1209))
                } else {
                    Image(systemName: needsDisplayName
                          ? "person.crop.circle.badge.plus"
                          : (usesTwoStepFlow ? "arrow.right" : "heart.fill"))
                        .font(.system(size: 14, weight: .bold))
                }
                Text(sending ? "Saving…" : (needsDisplayName ? "Add your name to send" : primarySaveTitle))
            }
        }
        .buttonStyle(CTAButtonStyle(
            isLoading: sending,
            isEnabled: needsDisplayName ? !sending : canSend
        ))
        .disabled(sending || (!needsDisplayName && !canSend))
        .padding(.top, 4)
        .accessibilityHint(needsDisplayName
            ? "Opens a short form to add your name"
            : (saveBlockedReason
               ?? (usesTwoStepFlow
                   ? "Saves your note, then lets you choose a recipient"
                   : "Saves this appreciation")))
    }

    // MARK: Message tools

    private var emojiShortcuts: some View {
        HStack(spacing: 8) {
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

            Text("\(message.count)/\(maxLength)")
                .font(Theme.body(12).monospacedDigit())
                .foregroundStyle(message.count > maxLength ? .red : Theme.textTertiary)
                .accessibilityLabel("\(message.count) of \(maxLength) characters")
        }
        .disabled(sending || polishing != nil || dictation.isListening || dictation.isTransitioning)
    }

    private var voiceOverlayButton: some View {
        let busy = dictation.isTransitioning
        let listening = dictation.isListening
        let showFilledChrome = listening || busy
        return Button {
            Task { await toggleVoiceDictation() }
        } label: {
            HStack(spacing: 5) {
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(showFilledChrome ? Color.white : Theme.coral)
                } else {
                    Image(systemName: listening ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .bold))
                        .symbolEffect(.pulse, isActive: listening)
                }
                if dictation.isStarting {
                    Text("Starting…")
                        .font(Theme.body(12, weight: .semibold))
                        .lineLimit(1)
                } else if dictation.isStopping {
                    Text("Processing…")
                        .font(Theme.body(12, weight: .semibold))
                        .lineLimit(1)
                } else if listening {
                    Text("Listening…")
                        .font(Theme.body(12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(showFilledChrome ? Color.white : Theme.coral)
            .padding(.horizontal, showFilledChrome ? 12 : 10)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(showFilledChrome ? Theme.coral : Theme.surface.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
            }
            .overlay {
                Capsule()
                    .strokeBorder(showFilledChrome ? Color.clear : Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(ScalePressButtonStyle())
        // Idle → start; Listening → stop; Starting/Processing → ignore taps.
        .disabled(!voiceControlsEnabled || busy)
        .accessibilityLabel(voiceAccessibilityLabel)
        .accessibilityHint(
            listening
                ? "Recording continues through pauses until you tap stop."
                : "Speak your appreciation. Recording stays on until you tap stop."
        )
    }

    private var voiceAccessibilityLabel: String {
        if dictation.isStarting { return "Starting dictation" }
        if dictation.isStopping { return "Processing dictation" }
        return dictation.isListening ? "Stop dictation" : "Dictate appreciation"
    }

    private var aiChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AppreciationAI.Style.allCases) { style in
                    aiChip(for: style)
                }
            }
        }
    }

    private func aiChip(for style: AppreciationAI.Style) -> some View {
        let isBusy = polishing == style
        return Button {
            Task { await runAI(style) }
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
                Text(isBusy ? style.busyTitle : style.buttonTitle)
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
                || dictation.isListening
                || dictation.isTransitioning
                || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .accessibilityLabel(style.buttonTitle)
    }

    private var voiceControlsEnabled: Bool {
        !sending && polishing == nil && !loadingPhoto
    }

    private func applyDictationTranscript() {
        let next = dictation.combinedText(maxLength: maxLength)
        guard message != next else { return }
        // Never let a late empty speech callback wipe text the user already saw.
        if next.isEmpty,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        message = next
    }

    private func toggleVoiceDictation() async {
        guard !dictation.isTransitioning else { return }
        error = nil
        dictation.errorMessage = nil
        messageFocused = true
        let starting = !dictation.isListening
        await dictation.toggle(baseText: message)
        if starting, dictation.isListening {
            trackFormStartIfNeeded()
        }
    }

    // MARK: Chrome helpers

    private func field(
        label: String? = nil,
        hint: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label, !label.isEmpty {
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
            }
            content()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )
        }
    }

    private var hasRecipient: Bool {
        linkedRecipient != nil
            || !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientOK = allowsEmptyRecipient || hasRecipient
        return recipientOK
            && !trimmed.isEmpty
            && trimmed.count <= maxLength
            && !loadingPhoto
            && polishing == nil
            && !dictation.isListening
            && !dictation.isTransitioning
            && !needsDisplayName
    }

    /// Explains why Save is disabled (toolbar can look active when only `.disabled`).
    private var saveBlockedReason: String? {
        guard !canSend, !sending else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsDisplayName { return "Add your name to send." }
        if polishing != nil { return "Wait for rewriting to finish." }
        if dictation.isStarting { return "Wait for the microphone to start." }
        if dictation.isStopping { return "Finishing dictation…" }
        if dictation.isListening { return "Stop dictation to save." }
        if loadingPhoto { return "Wait for the photo to finish loading." }
        if trimmed.isEmpty { return "Add a message to save." }
        if trimmed.count > maxLength { return "Shorten the message to \(maxLength) characters." }
        if !allowsEmptyRecipient && !hasRecipient {
            return "Add a recipient name or email to save."
        }
        return nil
    }

    private func insertEmoji(_ emoji: String) {
        guard polishing == nil, !dictation.isListening, !dictation.isTransitioning, !sending else { return }
        messageFocused = true
        // Insert at the caret via MessageEditor so the cursor lands after the emoji.
        pendingMessageInsert = MessageEditor.PendingInsert(text: emoji)
    }

    private func runAI(_ style: AppreciationAI.Style) async {
        guard polishing == nil else { return }
        polishing = style
        error = nil
        sendFailed = false
        messageFocused = false
        defer { polishing = nil }
        do {
            let original = message
            let rewritten = try await AppreciationAI.rewrite(original, style: style)
            let next = String(rewritten.prefix(maxLength))
            guard next != original else {
                self.error = "Couldn't find a different wording. Try adding a bit more detail, then tap again."
                messageFocused = true
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                messageBeforeAI = original
                message = next
            }
            Analytics.appreciationAIRewrite(tone: style.rawValue, formSessionId: formSessionId)
            messageFocused = true
        } catch {
            self.error = error.localizedDescription
            messageFocused = true
        }
    }

    // MARK: Photo

    /// Resign the keyboard first so the picker isn’t eaten by the first tap.
    private func openPhotosPicker() {
        guard !loadingPhoto, !sending else { return }
        photoError = nil
        messageFocused = false
        recipientFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            showPhotosPicker = true
        }
    }

    private func handlePickedMedia(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        photoError = nil
        messageFocused = false
        recipientFocused = false
        defer { loadingPhoto = false }

        if VideoProcessing.isVideoContentTypes(item.supportedContentTypes) {
            await handlePickedVideo(item)
        } else {
            await handlePickedPhoto(item)
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
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
            editableSourceImage = prepared
            cropItem = CropItem(image: prepared)
        } catch {
            photoError = "Couldn't load that photo. Try another one."
            photoItem = nil
        }
    }

    private func handlePickedVideo(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: VideoProcessing.MovieFile.self) else {
                photoError = VideoProcessing.VideoError.loadFailed.localizedDescription
                photoItem = nil
                return
            }
            let prepared = try await VideoProcessing.prepareForUpload(from: movie.url)
            try? FileManager.default.removeItem(at: movie.url)
            applyPreparedVideo(prepared)
            photoItem = nil
            messageFocused = true
        } catch let error as VideoProcessing.VideoError {
            photoError = error.localizedDescription
            photoItem = nil
        } catch {
            photoError = VideoProcessing.VideoError.loadFailed.localizedDescription
            photoItem = nil
        }
    }

    private func applyPreparedVideo(_ prepared: VideoProcessing.PreparedVideo) {
        clearVideoPreviewFile()
        attachedMediaKind = .video
        photoData = prepared.uploadData
        mediaContentType = prepared.contentType
        photoPreview = prepared.poster
        editableSourceImage = nil
        videoPreviewURL = prepared.previewFileURL
        videoPreviewIsLocalTemp = true
        removedPhoto = false
        existingMediaUrl = nil
        existingMediaType = nil
        photoError = nil
        cropItem = nil
    }

    private func applyCroppedPhoto(_ image: UIImage, source: UIImage? = nil) {
        clearVideoPreviewFile()
        attachedMediaKind = .image
        mediaContentType = "image/jpeg"
        if let source {
            editableSourceImage = source
        } else if editableSourceImage == nil {
            editableSourceImage = image
        }
        if let jpeg = ImageProcessing.jpegForUpload(image) {
            photoData = jpeg
            photoPreview = UIImage(data: jpeg) ?? image.downsampled(maxDimension: 720)
        } else if let jpeg = image.downsampled(maxDimension: ImageProcessing.postMaxDimension)
            .jpegData(compressionQuality: ImageProcessing.postJPEGQuality) {
            photoData = jpeg
            photoPreview = image.downsampled(maxDimension: 720)
        }
        removedPhoto = false
        existingMediaUrl = nil
        existingMediaType = nil
        photoError = nil
    }

    private func openCropEditor() {
        guard !showingVideo else { return }
        if let source = editableSourceImage ?? photoPreview {
            cropItem = CropItem(image: source)
            return
        }
        // Existing remote image — load then open cropper.
        guard let url = existingMediaURLResolved else { return }
        loadingPhoto = true
        Task {
            defer { loadingPhoto = false }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = await ImageProcessing.prepareForEditing(data) else {
                photoError = "Couldn't open that photo for editing."
                return
            }
            editableSourceImage = image
            photoPreview = image.downsampled(maxDimension: 800)
            cropItem = CropItem(image: image)
        }
    }

    private func clearVideoPreviewFile() {
        if videoPreviewIsLocalTemp, let url = videoPreviewURL {
            try? FileManager.default.removeItem(at: url)
        }
        videoPreviewURL = nil
        videoPreviewIsLocalTemp = false
    }

    private func clearPhoto() {
        clearVideoPreviewFile()
        photoData = nil
        mediaContentType = nil
        attachedMediaKind = nil
        photoPreview = nil
        editableSourceImage = nil
        photoItem = nil
        photoError = nil
        removedPhoto = true
        existingMediaUrl = nil
        existingMediaType = nil
        messageFocused = true
    }

    private func prefillIfNeeded() {
        guard !didPrefill else {
            autofocusMessageIfNeeded()
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
            let prepared = image.normalizedOrientation().downsampled(maxDimension: 1600)
            editableSourceImage = prepared
            cropItem = CropItem(image: prepared)
            ComposeShareStore.removeImage(fileName: fileName)
        }
        if ownsUnsentDraft, let draft = ComposeDraftStore.restore() {
            // Two-step write hides To — only restore the message; recipient is chosen on deliver.
            if !usesTwoStepFlow {
                recipient = draft.recipient
            }
            message = String(draft.message.prefix(maxLength))
            Analytics.captureDraftEvent(
                "draft_restored",
                hasRecipient: !usesTwoStepFlow
                    && !draft.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        autofocusMessageIfNeeded()
    }

    /// Heart-tab and other blank sends. November, Watch, and explicit prefills stay put.
    private var ownsUnsentDraft: Bool {
        ComposeDraftStore.ownsDraft(ComposeDraftStore.FormContext(
            isEditing: editingTarget != nil,
            analyticsSource: analyticsSource,
            hasInitialRecipient: !isBlank(initialRecipient),
            hasInitialProfile: initialRecipientProfile != nil,
            hasInitialMessage: !isBlank(initialMessage),
            hasInitialImage: !isBlank(initialImageFileName),
            hasInspiredBy: inspiredByGratitudeId != nil,
            hasCampaign: !isBlank(campaignId) || !isBlank(campaignHint)
        ))
    }

    /// Auto-opening compose after login shouldn't steal the first Cancel tap
    /// to the keyboard.
    private var shouldAutofocusMessage: Bool {
        analyticsSource != "app_open" && analyticsSource != "post_login"
    }

    private func autofocusMessageIfNeeded() {
        guard shouldAutofocusMessage else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard shouldAutofocusMessage else { return }
            messageFocused = true
        }
    }

    private func cancelCompose() {
        messageFocused = false
        recipientFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // Edit opened from the share screen — go back to that screen, not the one underneath.
        if created != nil, activeEditing != nil {
            suppressAbandonTracking = true
            if let created {
                applyEditing(created)
            }
            activeEditing = nil
            error = nil
            polishing = nil
            messageBeforeAI = nil
            sent = true
            return
        }
        trackAbandonIfNeeded()
        dismiss()
    }

    /// Pull the member's email from profiles so claim email can send
    /// without relying on the web API to fill recipient_email.
    /// Does not load phone — account phone numbers stay private to the member.
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
        // Clear create-only offer first so SuccessView can dismiss the sheet
        // without treating Edit as a “Not now” cooldown.
        offerEnjoymentPrompt = false
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
        mediaContentType = nil
        photoItem = nil
        photoPreview = nil
        editableSourceImage = nil
        clearVideoPreviewFile()
        attachedMediaKind = nil
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
            let isVideo = editing.mediaType?.lowercased().hasPrefix("video") == true
            if isVideo {
                attachedMediaKind = .video
                videoPreviewURL = url
                videoPreviewIsLocalTemp = false
                Task {
                    photoPreview = await VideoProcessing.thumbnail(from: url)
                }
            } else {
                attachedMediaKind = .image
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let image = await ImageProcessing.prepareForEditing(data) {
                        editableSourceImage = image
                        photoPreview = image.downsampled(maxDimension: 800)
                    }
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

    /// First time a Watch / empty pending row gets an email or a member — notify
    /// the way phone create does. Later edits don't send another claim email.
    private func deliverIfFirstRecipient(
        previous: Gratitude,
        updated: Gratitude,
        authorId: UUID
    ) {
        let hadDelivery = previous.recipientId != nil || !isBlank(previous.recipientEmail)
        let hasDelivery = updated.recipientId != nil || !isBlank(updated.recipientEmail)
        guard !hadDelivery, hasDelivery else { return }
        let author = authorId
        Task {
            do {
                try await GratitudeService.deliverPendingAppreciation(updated, authorId: author)
            } catch {
                // Watch / edit path — recipient is saved; claim email can be resent from Pending.
                Analytics.capture("appreciation_deliver_email_failed", [
                    "gratitude_id": updated.id.uuidString,
                    "source": "compose_edit",
                    "message": String(error.localizedDescription.prefix(120)),
                ])
            }
        }
    }

    // MARK: Send

    private func send() async {
        // Set before any await so a second tap cannot start another request.
        guard !sending else { return }
        guard let userId = auth.userId else { return }
        if needsDisplayName {
            showDisplayNameSheet = true
            return
        }
        guard canSend else { return }
        sending = true
        error = nil
        sendFailed = false
        defer { sending = false }
        do {
            await resolveRecipientBeforeSend()

            var mediaUrl: String?
            var mediaType: String?
            if let photoData, let kind = attachedMediaKind {
                switch kind {
                case .image:
                    let uploadData: Data
                    if let image = UIImage(data: photoData),
                       let compressed = ImageProcessing.jpegForUpload(image) {
                        uploadData = compressed
                    } else {
                        uploadData = photoData
                    }
                    let url = try await GratitudeService.uploadMedia(
                        data: uploadData,
                        contentType: mediaContentType ?? "image/jpeg",
                        userId: userId
                    )
                    mediaUrl = url.absoluteString
                    mediaType = "image"
                case .video:
                    let url = try await GratitudeService.uploadMedia(
                        data: photoData,
                        contentType: mediaContentType ?? "video/mp4",
                        userId: userId
                    )
                    mediaUrl = url.absoluteString
                    mediaType = "video"
                }
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
                // Profile embed can still be loading. Don't wipe that member if the
                // field is empty and the user didn't remove the chip.
                let typedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
                let preserveExistingMember = linked == nil
                    && typedRecipient.isEmpty
                    && !didClearRecipient
                    && editing.recipientId != nil
                let updated = try await GratitudeService.update(
                    id: editing.id,
                    update: GratitudeUpdate(
                        message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                        recipientEmail: preserveExistingMember
                            ? editing.recipientEmail
                            : (contact.email ?? linkedRecipientEmail ?? linked?.email),
                        // Only a phone the sender typed — never the member's private account phone.
                        recipientPhone: preserveExistingMember ? editing.recipientPhone : contact.phone,
                        recipientName: preserveExistingMember
                            ? editing.recipientName
                            : (contact.name ?? linked?.fullName ?? linked?.displayName),
                        recipientId: linked?.id ?? (preserveExistingMember ? editing.recipientId : nil),
                        visibility: visibility.rawValue,
                        mediaUrl: mediaUrl,
                        mediaType: mediaType
                    )
                )
                created = updated
                activeEditing = nil
                didCompleteSend = true
                if analyticsSource == "watch" {
                    WatchVoiceDraftStore.clear()
                }
                let recipientKind = linked != nil ? "member" : recipientTypeForAnalytics()
                Analytics.appreciationSubmitted(
                    gratitudeId: updated.id,
                    senderId: updated.authorId,
                    hasMedia: mediaUrl != nil,
                    messageLength: message.trimmingCharacters(in: .whitespacesAndNewlines).count,
                    hasRecipient: recipientKind != "none",
                    toMember: recipientKind == "member",
                    recipientType: recipientKind,
                    visibility: visibility.rawValue,
                    source: analyticsSource,
                    campaign: campaignId,
                    campaignDay: campaignDay,
                    formSessionId: formSessionId
                )
                onSaved?(updated)
                deliverIfFirstRecipient(previous: editing, updated: updated, authorId: userId)
                if updated.hasNoRecipient {
                    // Two-step: open deliver screen. Classic empty-recipient edit dismisses.
                    if usesTwoStepFlow {
                        sent = true
                        await UnsentDraftReminderStore.scheduleIfNeeded(for: updated)
                    } else {
                        dismiss()
                    }
                } else {
                    sent = true
                    UnsentDraftReminderStore.markRecipientAdded(id: updated.id)
                }
            } else {
                let new = NewGratitude(
                    authorId: userId,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    recipientEmail: contact.email ?? linkedRecipientEmail ?? linked?.email,
                    // Only a phone the sender typed — never the member's private account phone.
                    recipientPhone: contact.phone,
                    recipientName: contact.name ?? linked?.fullName ?? linked?.displayName,
                    recipientId: linked?.id,
                    visibility: visibility.rawValue,
                    mediaUrl: mediaUrl,
                    mediaType: mediaType,
                    source: analyticsSource == "watch" ? "watch" : "ios",
                    inspiredByGratitudeId: inspiredByGratitudeId
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
                didCompleteSend = true
                onSaved?(result)
                if analyticsSource == "watch" {
                    WatchVoiceDraftStore.clear()
                }
                if ownsUnsentDraft {
                    ComposeDraftStore.clearAfterSend()
                    Analytics.captureDraftEvent("sent", hasRecipient: hasRecipient)
                }
                EnjoymentPrompt.recordSuccessfulSend()
                offerEnjoymentPrompt = EnjoymentPrompt.shouldPresent(for: result)
                let recipientKind = linked != nil ? "member" : recipientTypeForAnalytics()
                Analytics.appreciationSubmitted(
                    gratitudeId: result.id,
                    senderId: result.authorId,
                    hasMedia: mediaUrl != nil,
                    messageLength: message.trimmingCharacters(in: .whitespacesAndNewlines).count,
                    hasRecipient: recipientKind != "none",
                    toMember: recipientKind == "member",
                    recipientType: recipientKind,
                    visibility: visibility.rawValue,
                    source: analyticsSource,
                    campaign: campaignId,
                    campaignDay: campaignDay,
                    formSessionId: formSessionId
                )
                if let parentId = inspiredByGratitudeId {
                    Analytics.capture("ripple_created", [
                        "parent_gratitude_id": parentId.uuidString.lowercased(),
                        "depth": 1,
                        "source": analyticsSource,
                        "form_session_id": formSessionId,
                    ])
                }
                NotificationCenter.default.post(name: .gratitudeCreated, object: result)
                sent = true
                if result.hasNoRecipient {
                    await UnsentDraftReminderStore.scheduleIfNeeded(for: result)
                } else {
                    UnsentDraftReminderStore.markRecipientAdded(id: result.id)
                }
                await refreshWidgetAfterSend()
                if let userId = auth.userId {
                    await StreakLiveActivityController.appreciationDidSend(userId: userId)
                }
            }
        } catch {
            priorErrorCount += 1
            sendFailed = true
            self.error = userFacingAppreciationSendMessage(for: error)
            Analytics.appreciationFailed(error: error, source: analyticsSource, formSessionId: formSessionId)
        }
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
            if linkedRecipient == nil {
                let parsed = parseRecipient(trimmed)
                if let match = await GratitudeService.matchingProfileId(
                    email: parsed.email,
                    phone: parsed.phone
                ), let profile = try? await GratitudeService.profile(id: match) {
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
        mediaContentType = nil
        attachedMediaKind = nil
        photoPreview = nil
        editableSourceImage = nil
        clearVideoPreviewFile()
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
        guestRecipientConfirmed = false
        recipientResults = []
        recipientSearching = false
        recipientSearchFinished = false
        didClearRecipient = false
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
    var preferredEmail: String? = nil
    var preferredName: String? = nil
    /// Create-path only; false when Success is shown again after an in-flow Edit.
    var offerEnjoymentPrompt: Bool = false
    var onEdit: () -> Void
    var onDone: () -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var showEnjoymentPrompt = false
    @State private var systemSharePayload: SystemSharePayload?

    private var shareURL: URL {
        gratitude.claimURL ?? gratitude.webURL
    }

    private var recipientEmail: String? {
        let value = gratitude.recipientEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var shareMessage: String {
        gratitude.pendingShareInviteMessage(shareURL: shareURL)
    }

    private var hasDeliverableRecipient: Bool {
        gratitude.recipientId != nil || recipientEmail != nil
    }

    private var headline: String {
        hasDeliverableRecipient
            ? "Your appreciation has been created!"
            : "Saved to Pending"
    }

    private var subtitle: String {
        if hasDeliverableRecipient {
            return "We've notified the recipient but it would help if you share a personalized note with the link so they can accept it."
        }
        if gratitude.hasNoRecipient {
            return "Add who it’s for with Edit, then share the link — or Done and finish later from Pending Appreciations."
        }
        return "Share the link so they can open and accept your appreciation."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.bottom, 28)

                VStack(spacing: 20) {
                    primaryCopyButton
                        .softNoteReveal(delay: 0.18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Send them the link")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .padding(.leading, 4)

                        VStack(spacing: 10) {
                            ShareActionRow(
                                title: "Text Message",
                                systemImage: "bubble.left.and.bubble.right.fill",
                                subtitle: gratitude.recipientPhone.map { "To \($0)" }
                                    ?? "Opens Messages with the link"
                            ) {
                                trackShare(channel: "text")
                                openSMS()
                            }

                            ShareActionRow(
                                title: "WhatsApp",
                                systemImage: "phone.bubble.fill",
                                subtitle: gratitude.recipientPhone.map { "To \($0)" }
                                    ?? "Opens Whatsapp with the link"
                            ) {
                                trackShare(channel: "whatsapp")
                                openWhatsApp()
                            }

                            ShareActionRow(
                                title: "Email",
                                systemImage: "envelope.fill",
                                subtitle: "Opens Email client with the link"
                            ) {
                                trackShare(channel: "email")
                                openMail()
                            }

                            ShareActionRow(
                                title: "Share",
                                systemImage: "square.and.arrow.up",
                                subtitle: "Messages, Mail, and more"
                            ) {
                                systemSharePayload = SystemSharePayload(
                                    items: SocialShare.pendingSystemShareItems(
                                        caption: gratitude.pendingShareInviteCaption,
                                        url: shareURL,
                                        title: gratitude.pendingShareEmailSubject
                                    )
                                )
                            }
                        }
                    }
                    .softNoteReveal(delay: 0.24)

                    ShareActionRow(
                        title: "Edit Appreciation",
                        systemImage: "square.and.pencil",
                        subtitle: "Change the message or details before they accept"
                    ) {
                        onEdit()
                    }
                    .softNoteReveal(delay: 0.3)
                }
                .padding(.horizontal, 24)

                Button(action: onDone) {
                    Text("Done")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .readableWidth(420)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $systemSharePayload) { payload in
            ActivityShareView(items: payload.items) { activityType in
                trackShare(channel: SocialShare.analyticsChannel(for: activityType))
            }
        }
        .sheet(isPresented: $showEnjoymentPrompt) {
            EnjoyingOpenThanksSheet(
                preferredEmail: preferredEmail,
                preferredName: preferredName,
                onFinished: { showEnjoymentPrompt = false }
            )
            .syncAppAppearance()
        }
        .onChange(of: offerEnjoymentPrompt) { _, offer in
            guard !offer, showEnjoymentPrompt else { return }
            EnjoymentPrompt.ignoreNextSheetDismiss = true
            showEnjoymentPrompt = false
        }
        .task(id: "\(gratitude.id.uuidString)-\(offerEnjoymentPrompt)") {
            guard offerEnjoymentPrompt else { return }
            guard EnjoymentPrompt.shouldPresent(for: gratitude) else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            // Re-check after delay in case eligibility changed.
            guard offerEnjoymentPrompt, EnjoymentPrompt.shouldPresent(for: gratitude) else { return }
            showEnjoymentPrompt = true
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            AppreciationMoment(size: 84)
                .padding(.top, 20)

            VStack(spacing: 10) {
                Text(headline)
                    .font(Theme.display(26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .softNoteReveal(delay: 0.1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var primaryCopyButton: some View {
        Button {
            UIPasteboard.general.string = shareURL.absoluteString
            trackShare(channel: "copy_link")
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
        .accessibilityHint("Copies the link to accept so you can paste it anywhere")
    }

    private func trackShare(channel: String) {
        let voice = AppreciationShareVoice.resolve(gratitude: gratitude, userId: auth.userId)
        let content = AppreciationShareContent(gratitude: gratitude, voice: voice)
        Analytics.appreciationShared(
            appreciationId: gratitude.id,
            channel: channel,
            voice: voice.rawValue,
            hasCard: false,
            hasPhoto: content.sharePhotoURL != nil
        )
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
        // Email in To when known; name-only leaves To blank so Mail can pick an address.
        // Body greets by name only — never by email address.
        var components = URLComponents()
        components.scheme = "mailto"
        if let email = gratitude.shareMailtoEmail {
            components.path = email
        }
        components.queryItems = [
            URLQueryItem(name: "subject", value: gratitude.pendingShareEmailSubject),
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
