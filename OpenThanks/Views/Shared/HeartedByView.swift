import SwiftUI

/// Avatar stack + “Alex and 3 others” summary that opens a sheet of everyone
/// who hearted the appreciation — mirrors the web `HeartedBy` component.
struct HeartedByView: View {
    let gratitudeId: UUID
    var heartCount: Int
    /// Opens the profile on the host navigation stack (same as Home search).
    var onOpenProfile: ((Profile) -> Void)? = nil
    /// Fired when the live hearters query returns a count (so the heart badge can catch up).
    var onCountResolved: ((Int) -> Void)? = nil

    @Environment(AuthService.self) private var auth
    @Environment(\.openProfile) private var openProfileEnv
    @State private var hearters: [Profile] = []
    @State private var resolvedCount = 0
    @State private var loaded = false
    @State private var showList = false
    /// Captured before the sheet opens. The sheet does not reliably inherit `openProfile`.
    @State private var hostedOpenProfile: ((Profile) -> Void)?
    @State private var sheetDetent: PresentationDetent = .medium

    /// Parent `heartCount` wins when it drops (optimistic unheart). `resolvedCount`
    /// may only raise a stale-low embed — never keep a removed heart on screen.
    private var displayCount: Int {
        if heartCount == 0 { return 0 }
        return max(heartCount, resolvedCount)
    }

    var body: some View {
        // VStack, not Group: Group forwards `.sheet` onto its child. When that
        // child is the control that opens the sheet, row taps inside the sheet
        // are delivered to it and the list does nothing.
        VStack(spacing: 0) {
            if displayCount > 0 {
                HStack(spacing: 8) {
                    avatarStack
                    if let summary {
                        Text(summary)
                            .font(Theme.body(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Read the opener here, outside the sheet. The sheet does not
                    // reliably inherit `openProfile`.
                    hostedOpenProfile = onOpenProfile ?? openProfileEnv
                    sheetDetent = .medium
                    showList = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .onChange(of: heartCount) { oldCount, newCount in
            if newCount < oldCount {
                applyHeartCountDrop(newCount)
            } else if newCount > oldCount {
                // Show the viewer’s name immediately — the hearts insert may lag.
                insertOptimisticViewerIfNeeded()
                resolvedCount = max(resolvedCount, newCount)
            }
        }
        .task(id: "\(gratitudeId.uuidString)-\(heartCount)") {
            await load()
        }
        .sheet(isPresented: $showList) {
            heartersSheet
        }
    }

    /// Drop stale avatars/names immediately when the parent count falls (unheart).
    private func applyHeartCountDrop(_ newCount: Int) {
        if newCount == 0 {
            resolvedCount = 0
            hearters = []
            return
        }
        guard newCount < resolvedCount else { return }
        resolvedCount = newCount
        if hearters.count > newCount {
            hearters = Array(hearters.prefix(newCount))
        }
    }

    /// Prefers `auth.currentProfile` so a just-hearted note shows a name before the query catches up.
    private func insertOptimisticViewerIfNeeded() {
        guard let me = auth.currentProfile else { return }
        if hearters.contains(where: { $0.id == me.id }) { return }
        hearters.insert(me, at: 0)
    }

    // MARK: Inline

    @ViewBuilder
    private var avatarStack: some View {
        let preview = Array(hearters.prefix(3))
        if preview.isEmpty {
            ZStack {
                Circle()
                    .fill(Theme.coral.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
        } else {
            HStack(spacing: -8) {
                ForEach(Array(preview.enumerated()), id: \.element.id) { _, person in
                    AvatarView(profile: person, size: 26)
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                }
            }
        }
    }

    private var summary: String? {
        let preview = Array(hearters.prefix(3))
        guard !preview.isEmpty else { return nil }
        if preview.count == 1 {
            return preview[0].firstName
        }
        if preview.count >= 2, displayCount == 2 {
            return "\(preview[0].firstName) and \(preview[1].firstName)"
        }
        return "\(preview[0].firstName) and \(displayCount - 1) others"
    }

    private var accessibilityLabel: String {
        let noun = displayCount == 1 ? "person" : "people"
        return "See who hearted this — \(displayCount) \(noun)"
    }

    // MARK: Sheet

    private var heartersSheet: some View {
        NavigationStack {
            Group {
                if !loaded && hearters.isEmpty {
                    ProgressView()
                        .tint(Theme.coral)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hearters.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Theme.coral.opacity(0.7))
                        Text("No hearts yet")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Be the first to heart this appreciation.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List {
                        ForEach(hearters) { person in
                            NavigationLink {
                                // Push inside the sheet so the profile starts on the tap.
                                // Closing the sheet and pushing afterward left a pause.
                                UserProfileView(profile: person)
                                    .navigationBarBackButtonHidden(true)
                                    .toolbar {
                                        ToolbarItem(placement: .topBarLeading) {
                                            Button {
                                                showList = false
                                            } label: {
                                                Image(systemName: "chevron.backward")
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundStyle(Theme.coral)
                                            }
                                            .accessibilityLabel("Back")
                                        }
                                    }
                                    .onAppear { sheetDetent = .large }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(profile: person, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.displayName)
                                            .font(Theme.body(15, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        if !person.username.isEmpty {
                                            Text("@\(person.username)")
                                                .font(Theme.body(13))
                                                .foregroundStyle(Theme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View \(person.displayName)'s profile")
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Theme.background)
                            .listRowSeparator(.hidden)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, 56)
                                    .allowsHitTesting(false)
                            }
                        }

                        if displayCount > hearters.count {
                            Text("and \(displayCount - hearters.count) more")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                                .listRowBackground(Theme.background)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 0)
                }
            }
            .background(Theme.background)
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showList = false }
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
            }
            // Only used when a profile opened from here pushes another screen.
            .appDestinations()
            .environment(\.openProfile, hostedOpenProfile ?? onOpenProfile ?? openProfileEnv)
            .task { await load(force: true) }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .syncAppAppearance()
    }

    private var sheetTitle: String {
        let n = displayCount
        return n == 1 ? "1 heart" : "\(n) hearts"
    }

    // MARK: Data

    private func load(force: Bool = false) async {
        if !force, loaded, heartCount == resolvedCount, !hearters.isEmpty || heartCount == 0 {
            return
        }
        do {
            var result = try await GratitudeService.hearters(for: gratitudeId)
            guard !Task.isCancelled else { return }

            // Optimistic heart often beats the write — a stale empty list used to
            // wipe the name until pull-to-refresh. Retry once, then keep the floor.
            if result.count < heartCount {
                if heartCount > 0 { insertOptimisticViewerIfNeeded() }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                let retry = try await GratitudeService.hearters(for: gratitudeId)
                if retry.count >= result.count {
                    result = retry
                }
            }

            if result.count < heartCount {
                // Still lagging — keep optimistic avatars / parent count.
                if heartCount > 0 { insertOptimisticViewerIfNeeded() }
                resolvedCount = max(resolvedCount, heartCount, result.count)
                loaded = true
                // Never publish a lower count back to the parent (that undid the heart).
                onCountResolved?(max(heartCount, result.count))
                return
            }

            hearters = result.hearters
            resolvedCount = result.count
            loaded = true
            onCountResolved?(result.count)
        } catch {
            if !error.isCancellation {
                loaded = true
            }
        }
    }
}
