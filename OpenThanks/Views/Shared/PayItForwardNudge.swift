import SwiftUI

/// Gentle post-accept prompt to continue a gratitude ripple — with concrete paths.
struct PayItForwardNudgeCard: View {
    var fromName: String?
    /// Prefills To when thanking the sender back.
    var senderProfile: Profile? = nil
    var senderEmail: String? = nil
    /// Message they just accepted — drives the echo-gift chip + thank-back draft.
    var acceptedMessage: String? = nil
    var onChoose: (PostAcceptChoice) -> Void
    var onDismiss: (() -> Void)? = nil
    var onRequestCalendarConnect: (() -> Void)? = nil
    /// When all three are set, `pay_it_forward_shown` fires once from `onAppear`.
    var analyticsParentId: UUID? = nil
    var analyticsSurface: String? = nil
    var analyticsSource: String? = nil

    @State private var didCaptureShown = false
    @State private var calendarConnected = false
    @State private var faces: [CalendarThankFace] = []
    @State private var facesLoaded = false
    @State private var remindBusy = false
    @State private var remindScheduled = false

    private var echoTheme: GratitudeEchoTheme {
        GratitudeEchoTheme.detect(from: acceptedMessage)
    }

    private var canThankBack: Bool {
        let name = fromName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty && name.lowercased() != "someone"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "water.waves")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text(PayItForwardPromptCopy.title(fromName: fromName))
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }

            Text(PayItForwardPromptCopy.body)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(PayItForwardPromptCopy.choosePrompt)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 2)

            VStack(spacing: 8) {
                if canThankBack {
                    pathChip(
                        title: PayItForwardPromptCopy.thankBackChipTitle(fromName: fromName),
                        systemImage: "arrow.uturn.left"
                    ) {
                        choose(thankBackChoice())
                    }
                }

                ForEach(PayItForwardPromptCopy.questionPaths(echoTheme: echoTheme)) { path in
                    pathChip(
                        title: PayItForwardPromptCopy.chipTitle(for: path, echoTheme: echoTheme),
                        systemImage: path == .echoGift ? "arrow.triangle.2.circlepath" : "person"
                    ) {
                        choose(
                            PayItForwardPromptCopy.choice(path: path, echoTheme: echoTheme)
                        )
                    }
                }
            }

            calendarBlock

            remindBlock
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.coral.opacity(0.35), lineWidth: 1)
                )
        )
        .onAppear(perform: captureShownIfNeeded)
        .task { await loadCalendarFaces() }
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PayItForwardPromptCopy.calendarSection)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if !facesLoaded {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.primary)
            } else if calendarConnected, !faces.isEmpty {
                FlowFaceChips(faces: faces) { face in
                    choose(
                        PayItForwardPromptCopy.choice(
                            path: .calendarPerson,
                            recipientName: face.personName,
                            recipientEmail: face.email,
                            meetingTitle: face.meetingTitle,
                            messageOverride: face.starterMessage
                        )
                    )
                }
            } else if calendarConnected {
                Text(PayItForwardPromptCopy.calendarEmpty)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                pathChip(
                    title: PostAcceptPath.calendarConnect.chipTitle,
                    systemImage: "calendar"
                ) {
                    if let onRequestCalendarConnect {
                        onRequestCalendarConnect()
                    } else {
                        choose(PayItForwardPromptCopy.choice(path: .calendarConnect))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Remind

    private var remindBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            pathChip(
                title: remindScheduled
                    ? "Reminder set for tonight"
                    : PostAcceptPath.remindTonight.chipTitle,
                systemImage: "bell"
            ) {
                Task { await scheduleRemindTonight() }
            }
            .disabled(remindBusy || remindScheduled)
            .opacity(remindScheduled ? 0.7 : 1)

            Text(PayItForwardPromptCopy.remindDetail)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 2)
    }

    private func pathChip(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 22)
                Text(title)
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.coral.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func choose(_ choice: PostAcceptChoice) {
        onChoose(choice)
    }

    private func thankBackChoice() -> PostAcceptChoice {
        let email = senderEmail
            ?? senderProfile?.email
        let name = fromName
            ?? senderProfile?.fullName
            ?? senderProfile?.displayName
        return PayItForwardPromptCopy.choice(
            path: .thankBack,
            echoTheme: echoTheme,
            recipientName: name,
            recipientEmail: email,
            acceptedMessage: acceptedMessage
        )
    }

    private func scheduleRemindTonight() async {
        guard !remindBusy, !remindScheduled else { return }
        remindBusy = true
        defer { remindBusy = false }
        let choice = PayItForwardPromptCopy.choice(
            path: .remindTonight,
            echoTheme: echoTheme
        )
        let ok = await NotificationService.schedulePostAcceptRemind(
            messageDraft: choice.message,
            inspiredByGratitudeId: analyticsParentId,
            inspiredByAuthorName: fromName
        )
        if ok {
            remindScheduled = true
            // Treat as a successful engagement so hosts don't count a dismiss.
            onChoose(choice)
        }
    }

    private func loadCalendarFaces() async {
        calendarConnected = CalendarMeetingAggregator.hasAnyConnectedSource
        if calendarConnected {
            faces = await GratitudeOpportunityRanker.topPeople(limit: 3)
        } else {
            faces = []
        }
        facesLoaded = true
    }

    /// Impression only. PostHog capture enqueues; this does not touch the layout.
    private func captureShownIfNeeded() {
        guard !didCaptureShown,
              let analyticsParentId,
              let analyticsSurface,
              let analyticsSource else { return }
        didCaptureShown = true
        Analytics.payItForwardShown(
            parentGratitudeId: analyticsParentId,
            surface: analyticsSurface,
            source: analyticsSource
        )
    }
}

/// Horizontal name chips for today's meeting faces.
private struct FlowFaceChips: View {
    let faces: [CalendarThankFace]
    var onSelect: (CalendarThankFace) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(faces) { face in
                Button {
                    onSelect(face)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(face.personName)
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(face.subtitle)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thank \(face.personName)")
            }
        }
    }
}

/// Sheet wrapper used right after accepting from the Home feed.
struct PayItForwardSheet: View {
    var fromName: String?
    var senderProfile: Profile? = nil
    var senderEmail: String? = nil
    var acceptedMessage: String? = nil
    var parentGratitudeId: UUID?
    var analyticsSurface: String
    var analyticsSource: String
    var onChoose: (PostAcceptChoice) -> Void
    var onRequestCalendarConnect: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var detentHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Theme.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            ScrollView {
                PayItForwardNudgeCard(
                    fromName: fromName,
                    senderProfile: senderProfile,
                    senderEmail: senderEmail,
                    acceptedMessage: acceptedMessage,
                    onChoose: { choice in
                        // Tell the host this was a tap before `dismiss()` flips the
                        // presentation binding, so that path is not counted as a dismiss.
                        onChoose(choice)
                        // Remind-tonight stays on the sheet briefly so they see "Reminder set".
                        if choice.path != .remindTonight {
                            dismiss()
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                                dismiss()
                            }
                        }
                    },
                    onDismiss: {
                        dismiss()
                    },
                    onRequestCalendarConnect: onRequestCalendarConnect.map { action in
                        {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                action()
                            }
                        }
                    },
                    analyticsParentId: parentGratitudeId,
                    analyticsSurface: analyticsSurface,
                    analyticsSource: analyticsSource
                )
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 520)

            Button(PayItForwardPromptCopy.notNow) {
                dismiss()
            }
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.background)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PayItForwardSheetHeightKey.self,
                    value: geo.size.height
                )
            }
        }
        .onPreferenceChange(PayItForwardSheetHeightKey.self) { height in
            guard height.isFinite, height > 0, abs(height - detentHeight) > 1 else { return }
            detentHeight = min(height, 640)
        }
        .presentationDetents([.height(max(detentHeight, 360)), .large])
        .presentationDragIndicator(.hidden)
    }
}

private enum PayItForwardSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
