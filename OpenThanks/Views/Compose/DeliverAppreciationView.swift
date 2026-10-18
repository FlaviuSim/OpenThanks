import SwiftUI

/// Step 2 after saving a no-recipient appreciation: add who it’s for, choose
/// visibility, and share the claim link. The draft is already persisted.
struct DeliverAppreciationView: View {
    @Binding var gratitude: Gratitude
    var preferredEmail: String? = nil
    var preferredName: String? = nil
    var offerEnjoymentPrompt: Bool = false
    var onEdit: () -> Void
    var onDone: () -> Void
    var onUpdated: ((Gratitude) -> Void)? = nil

    @Environment(AuthService.self) private var auth
    @Environment(UserBlockService.self) private var userBlocks
    @Environment(\.openURL) private var openURL

    @State private var recipient = ""
    @State private var linkedRecipient: Profile?
    @State private var linkedRecipientEmail: String?
    @State private var guestRecipientConfirmed = false
    @State private var recipientResults: [Profile] = []
    @State private var recipientSearching = false
    @State private var recipientSearchFinished = false
    @State private var visibility: GratitudeVisibility = .public
    @State private var savingRecipient = false
    @State private var savingVisibility = false
    @State private var error: String?
    @State private var copied = false
    @State private var showEnjoymentPrompt = false
    @State private var systemSharePayload: SystemSharePayload?
    @State private var didPrefillRecipient = false

    @FocusState private var recipientFocused: Bool

    private var shareURL: URL {
        gratitude.claimURL ?? gratitude.webURL
    }

    private var shareMessage: String {
        gratitude.pendingShareInviteMessage(shareURL: shareURL)
    }

    private var hasDeliverableRecipient: Bool {
        !gratitude.hasNoRecipient
            || linkedRecipient != nil
            || guestRecipientConfirmed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.bottom, 24)

                VStack(spacing: 22) {
                    recipientBlock
                        .softNoteReveal(delay: 0.12)

                    shareBlock
                        .softNoteReveal(delay: 0.2)

                    visibilityBlock
                        .softNoteReveal(delay: 0.28)

                    if let error {
                        Text(error)
                            .font(Theme.body(13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    ShareActionRow(
                        title: "Edit Appreciation",
                        systemImage: "square.and.pencil",
                        subtitle: "Change the message or photo"
                    ) {
                        onEdit()
                    }
                    .softNoteReveal(delay: 0.34)
                }
                .padding(.horizontal, 24)

                Button {
                    finishAndDismiss()
                } label: {
                    Text("Done")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
                .accessibilityHint("Keeps your draft in Pending Appreciations")
            }
            .readableWidth(420)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $systemSharePayload) { payload in
            ActivityShareView(items: payload.items) { activityType in
                noteShared(channel: SocialShare.analyticsChannel(for: activityType))
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
        .onAppear {
            prefillIfNeeded()
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
            guard offerEnjoymentPrompt, EnjoymentPrompt.shouldPresent(for: gratitude) else { return }
            showEnjoymentPrompt = true
        }
        .task(id: recipientSearchQuery) {
            await runRecipientSearch(for: recipientSearchQuery)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: 18) {
            AppreciationMoment(size: 84)
                .padding(.top, 20)

            VStack(spacing: 10) {
                Text(hasDeliverableRecipient
                     ? "Ready to send"
                     : "Your note is saved")
                    .font(Theme.display(26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(hasDeliverableRecipient
                     ? "Share the link so they can open and accept your appreciation."
                     : "Add who it’s for, or share the link now — you can finish later from Pending.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Text(gratitude.message)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            .softNoteReveal(delay: 0.08)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var recipientBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send to")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, 4)

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

            if savingRecipient {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Saving recipient…")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.leading, 4)
            }
        }
    }

    private var shareBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share the link")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, 4)

            Button {
                UIPasteboard.general.string = shareURL.absoluteString
                noteShared(channel: "copy_link")
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

            VStack(spacing: 10) {
                ShareActionRow(
                    title: "Text Message",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    subtitle: gratitude.recipientPhone.map { "To \($0)" }
                        ?? "Opens Messages with the link"
                ) {
                    noteShared(channel: "text")
                    openSMS()
                }

                ShareActionRow(
                    title: "WhatsApp",
                    systemImage: "phone.bubble.fill",
                    subtitle: gratitude.recipientPhone.map { "To \($0)" }
                        ?? "Opens WhatsApp with the link"
                ) {
                    noteShared(channel: "whatsapp")
                    openWhatsApp()
                }

                ShareActionRow(
                    title: "Email",
                    systemImage: "envelope.fill",
                    subtitle: "Opens Email with the link"
                ) {
                    noteShared(channel: "email")
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
    }

    private var visibilityBlock: some View {
        Button {
            guard !savingVisibility else { return }
            let next: GratitudeVisibility = visibility == .public ? .private : .public
            Task { await saveVisibility(next) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.surfaceRaised)
                        .frame(width: 40, height: 40)
                    if savingVisibility {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: visibility == .public ? "globe" : "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(visibility == .public ? "Public" : "Private")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(visibility == .public
                          ? "In the feed once they accept"
                          : "Only you and the recipient can see")
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
        .disabled(savingVisibility)
        .sensoryFeedback(.selection, trigger: visibility)
        .accessibilityHint("Switches between public and private")
    }

    // MARK: - Recipient field (mirrors compose)

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
                    .onSubmit {
                        if shouldShowAddGuestRow {
                            confirmGuestRecipient()
                        }
                    }
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
                clearLinkedRecipient()
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
                clearGuestRecipient()
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
                    Text("We’ll notify them when you share the link")
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

    // MARK: - Actions

    private func prefillIfNeeded() {
        guard !didPrefillRecipient else { return }
        didPrefillRecipient = true
        visibility = gratitude.visibility ?? .public
        if let profile = gratitude.recipient {
            linkedRecipient = profile
            linkedRecipientEmail = profile.email.flatMap {
                let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : AuthService.normalizedEmail(t)
            }
        } else if let name = gratitude.recipientName, !name.isEmpty {
            recipient = name
            guestRecipientConfirmed = true
        } else if let email = gratitude.recipientEmail, !email.isEmpty {
            recipient = email
            guestRecipientConfirmed = true
        }
    }

    private func finishAndDismiss() {
        recipientFocused = false
        Task {
            if gratitude.hasNoRecipient, !UnsentDraftReminderStore.hasShared(id: gratitude.id) {
                await UnsentDraftReminderStore.scheduleIfNeeded(for: gratitude)
            }
            await MainActor.run { onDone() }
        }
    }

    private func noteShared(channel: String) {
        UnsentDraftReminderStore.markShared(id: gratitude.id)
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

    private func selectLinkedRecipient(_ profile: Profile) {
        linkedRecipient = profile
        guestRecipientConfirmed = false
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
        Task {
            await loadLinkedRecipientContact(profileId: profile.id)
            await persistRecipient()
        }
    }

    private func confirmGuestRecipient() {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guestRecipientConfirmed = true
        recipient = trimmed
        recipientResults = []
        recipientSearching = false
        recipientSearchFinished = false
        recipientFocused = false
        Task { await persistRecipient() }
    }

    private func clearLinkedRecipient() {
        linkedRecipient = nil
        linkedRecipientEmail = nil
        guestRecipientConfirmed = false
        recipient = ""
        recipientFocused = true
        Task { await persistRecipientCleared() }
    }

    private func clearGuestRecipient() {
        guestRecipientConfirmed = false
        recipient = ""
        recipientFocused = true
        Task { await persistRecipientCleared() }
    }

    private func persistRecipient() async {
        guard let userId = auth.userId else { return }
        savingRecipient = true
        error = nil
        defer { savingRecipient = false }

        await resolveRecipientBeforeSave()

        let previous = gratitude
        let linked = linkedRecipient
        let contact: (name: String?, email: String?, phone: String?)
        if linked != nil {
            contact = (nil, nil, nil)
        } else {
            contact = parseRecipient(recipient)
        }

        do {
            var updated = try await GratitudeService.update(
                id: gratitude.id,
                update: GratitudeUpdate(
                    message: gratitude.message,
                    recipientEmail: contact.email ?? linkedRecipientEmail ?? linked?.email,
                    recipientPhone: contact.phone,
                    recipientName: contact.name ?? linked?.fullName ?? linked?.displayName,
                    recipientId: linked?.id,
                    visibility: visibility.rawValue,
                    mediaUrl: gratitude.mediaUrl,
                    mediaType: gratitude.mediaType
                )
            )
            if updated.recipient == nil, let linked {
                updated.recipient = linked
            }
            if isBlank(updated.recipientName), let linked {
                updated.recipientName = linked.fullName ?? linked.displayName
            }
            if isBlank(updated.recipientEmail) {
                updated.recipientEmail = linkedRecipientEmail ?? linked?.email
            }
            gratitude = updated
            onUpdated?(updated)
            UnsentDraftReminderStore.markRecipientAdded(id: updated.id)
            deliverIfFirstRecipient(previous: previous, updated: updated, authorId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func persistRecipientCleared() async {
        savingRecipient = true
        error = nil
        defer { savingRecipient = false }
        do {
            let updated = try await GratitudeService.update(
                id: gratitude.id,
                update: GratitudeUpdate(
                    message: gratitude.message,
                    recipientEmail: nil,
                    recipientPhone: nil,
                    recipientName: nil,
                    recipientId: nil,
                    visibility: visibility.rawValue,
                    mediaUrl: gratitude.mediaUrl,
                    mediaType: gratitude.mediaType
                )
            )
            gratitude = updated
            onUpdated?(updated)
            if !UnsentDraftReminderStore.hasShared(id: updated.id) {
                await UnsentDraftReminderStore.scheduleIfNeeded(for: updated)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveVisibility(_ next: GratitudeVisibility) async {
        savingVisibility = true
        error = nil
        defer { savingVisibility = false }
        do {
            let updated = try await GratitudeService.update(
                id: gratitude.id,
                update: GratitudeUpdate(
                    message: gratitude.message,
                    recipientEmail: gratitude.recipientEmail,
                    recipientPhone: gratitude.recipientPhone,
                    recipientName: gratitude.recipientName,
                    recipientId: gratitude.recipientId,
                    visibility: next.rawValue,
                    mediaUrl: gratitude.mediaUrl,
                    mediaType: gratitude.mediaType
                )
            )
            visibility = next
            gratitude = updated
            onUpdated?(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deliverIfFirstRecipient(
        previous: Gratitude,
        updated: Gratitude,
        authorId: UUID
    ) {
        let hadDelivery = previous.recipientId != nil || !isBlank(previous.recipientEmail)
        let hasDelivery = updated.recipientId != nil || !isBlank(updated.recipientEmail)
        guard !hadDelivery, hasDelivery else { return }
        Task { await GratitudeService.deliverPendingAppreciation(updated, authorId: authorId) }
    }

    private func resolveRecipientBeforeSave() async {
        if linkedRecipient == nil {
            let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("@") {
                let handle = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !handle.isEmpty,
                   let profile = try? await GratitudeService.profile(username: handle) {
                    linkedRecipient = profile
                    guestRecipientConfirmed = false
                }
            }
            if linkedRecipient == nil {
                let parsed = parseRecipient(trimmed)
                if let match = await GratitudeService.matchingProfileId(
                    email: parsed.email,
                    phone: parsed.phone
                ), let profile = try? await GratitudeService.profile(id: match) {
                    linkedRecipient = profile
                    guestRecipientConfirmed = false
                }
            }
        }
        if let linked = linkedRecipient, isBlank(linkedRecipientEmail) {
            await loadLinkedRecipientContact(profileId: linked.id)
        }
    }

    private func loadLinkedRecipientContact(profileId: UUID) async {
        guard linkedRecipient?.id == profileId else { return }
        guard let contact = try? await GratitudeService.profileContact(id: profileId) else { return }
        if let email = contact.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            linkedRecipientEmail = AuthService.normalizedEmail(email)
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

    private func parseRecipient(_ raw: String)
        -> (name: String?, email: String?, phone: String?) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil, nil) }
        if looksLikeEmail(value) {
            return (nil, AuthService.normalizedEmail(value), nil)
        }
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

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
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
