import SwiftUI

/// Avatar stack + “Alex and 3 others” summary that opens a sheet of everyone
/// who hearted the appreciation — mirrors the web `HeartedBy` component.
struct HeartedByView: View {
    let gratitudeId: UUID
    var heartCount: Int
    /// Opens the profile on the host navigation stack (same as Home search).
    var onOpenProfile: ((Profile) -> Void)? = nil

    @Environment(\.openProfile) private var openProfileEnv
    @State private var hearters: [Profile] = []
    @State private var resolvedCount = 0
    @State private var loaded = false
    @State private var showList = false
    /// Captured before the sheet opens. Custom environment values (and the
    /// presenting button) are not a reliable way to open a profile from inside
    /// the sheet — row taps were landing on the summary button underneath.
    @State private var hostedOpenProfile: ((Profile) -> Void)?
    /// Class so `onDismiss` sees the person chosen in the same turn the sheet closes.
    @State private var pendingOpen = PendingProfileOpen()
    /// Fallback when this screen has no host navigation callback.
    @State private var sheetPath = NavigationPath()

    private final class PendingProfileOpen {
        var profile: Profile?
        var open: ((Profile) -> Void)?
    }

    private var displayCount: Int { max(heartCount, resolvedCount) }

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
                    sheetPath = NavigationPath()
                    showList = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .task(id: "\(gratitudeId.uuidString)-\(heartCount)") {
            await load()
        }
        .sheet(isPresented: $showList, onDismiss: openPendingProfileIfNeeded) {
            heartersSheet
        }
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
        NavigationStack(path: $sheetPath) {
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
                            Button {
                                selectProfile(person)
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
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.textTertiary)
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
            // Only used when there is no host stack to push onto.
            .appDestinations()
            .task { await load(force: true) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .syncAppAppearance()
    }

    private var sheetTitle: String {
        let n = displayCount
        return n == 1 ? "1 heart" : "\(n) hearts"
    }

    private func selectProfile(_ person: Profile) {
        // Prefer the opener captured outside the sheet. `onOpenProfile` is a
        // stored callback (iPad split); `openProfileEnv` is a last resort.
        let open = hostedOpenProfile ?? onOpenProfile ?? openProfileEnv
        if let open {
            pendingOpen.profile = person
            pendingOpen.open = open
            showList = false
        } else {
            sheetPath.append(person)
        }
    }

    private func openPendingProfileIfNeeded() {
        let profile = pendingOpen.profile
        let open = pendingOpen.open
        pendingOpen.profile = nil
        pendingOpen.open = nil
        guard let profile, let open else { return }
        // A NavigationPath push during the sheet dismiss animation is ignored.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            open(profile)
        }
    }

    // MARK: Data

    private func load(force: Bool = false) async {
        if !force, loaded, heartCount == resolvedCount, !hearters.isEmpty || heartCount == 0 {
            return
        }
        do {
            let result = try await GratitudeService.hearters(for: gratitudeId)
            guard !Task.isCancelled else { return }
            hearters = result.hearters
            resolvedCount = result.count
            loaded = true
        } catch {
            if !error.isCancellation {
                loaded = true
            }
        }
    }
}
