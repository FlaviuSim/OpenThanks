import SwiftUI

/// Own-profile tab: your profile plus the settings entry point.
struct ProfileView: View {
    @Binding var path: NavigationPath
    @Binding var showSettings: Bool
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let profile = auth.currentProfile {
                    UserProfileView(profile: profile)
                } else {
                    ProgressView().tint(Theme.coral)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .appDestinations()
            .environment(\.openProfile) { path.append($0) }
            .syncAppAppearance()
        }
    }
}

/// Any user's profile: header, nonprofit spotlight, stats, and
/// Ripple Effect / Appreciations received / given — accepted posts only,
/// private posts shown only to the people involved in them.
struct UserProfileView: View {
    enum Section: String, CaseIterable {
        case ripple = "Ripple Effect"
        case received = "Appreciations received"
        case sent = "Appreciations given"
    }

    let profile: Profile
    var initialSection: Section? = nil
    @Environment(AuthService.self) private var auth

    @State private var freshProfile: Profile?
    @State private var section: Section
    @State private var stats = ProfileStats()
    @State private var sent: [Gratitude] = []
    @State private var received: [Gratitude] = []
    @State private var inspirations: [Inspiration] = []
    @State private var ripplePassOns: [Gratitude] = []
    @State private var loaded = false
    @State private var fullScreenAvatarURL: URL?
    @State private var showCompose = false
    @State private var composeAnalyticsSource = "profile_thank"
    @State private var composeUsesProfileRecipient = true
    @State private var pendingSentCount = 0
    @State private var showReportSheet = false
    @State private var didTrackRippleTab = false

    init(profile: Profile, initialSection: Section? = nil) {
        self.profile = profile
        self.initialSection = initialSection
        _section = State(initialValue: initialSection ?? .ripple)
    }

    private var shownProfile: Profile {
        // Own profile must track live auth state — local `freshProfile` would
        // otherwise keep the pre-edit avatar until pull-to-refresh.
        if isOwnProfile, let current = auth.currentProfile {
            return current
        }
        return freshProfile ?? profile
    }
    private var isOwnProfile: Bool { auth.userId == profile.id }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if shownProfile.favoriteNonprofitName != nil { nonprofitCard }
                sectionSwitcher
                if section != .ripple, isOwnProfile, pendingSentCount > 0 {
                    PendingAppreciationsBanner(count: pendingSentCount)
                }
                sectionContent
            }
            .padding(.horizontal, 20)
            .tabChromeBottomPadding()
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle(isOwnProfile ? "Profile" : shownProfile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showReportSheet = true
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentSheet(
                target: .profile(shownProfile.id),
                title: "Report \(shownProfile.displayName)’s profile if it violates our community standards."
            )
        }
        .task(id: profile.id) { await load() }
        .refreshable { await load() }
        .animation(.easeInOut(duration: 0.2), value: section)
        .onChange(of: auth.currentProfile) { _, newValue in
            guard isOwnProfile, let newValue else { return }
            freshProfile = newValue
            applyProfileUpdate(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusProfileInspired)) { _ in
            guard isOwnProfile else { return }
            section = .ripple
        }
        .onChange(of: section) { _, newSection in
            if newSection == .ripple { trackRippleTabIfNeeded() }
        }
        .onAppear {
            if section == .ripple { trackRippleTabIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gratitudeAccepted)) { note in
            guard let gratitude = note.object as? Gratitude else { return }
            applyAccepted(gratitude)
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidUpdate)) { note in
            guard let updated = note.object as? Profile, updated.id == profile.id else { return }
            freshProfile = updated
            applyProfileUpdate(updated)
        }
        .fullScreenCover(item: $fullScreenAvatarURL) { url in
            FullScreenImageView(url: url)
        }
        .composeCover(isPresented: $showCompose) {
            ComposeView(
                initialRecipientProfile: composeUsesProfileRecipient && !isOwnProfile
                    ? shownProfile
                    : nil,
                analyticsSource: composeAnalyticsSource
            )
        }
    }

    private func trackRippleTabIfNeeded() {
        guard !didTrackRippleTab else { return }
        didTrackRippleTab = true
        Analytics.capture("ripple_tab_viewed", [
            "is_own_profile": isOwnProfile,
            "profile_id": profile.id.uuidString.lowercased(),
        ])
    }

    private func openComposeFromRipple(source: String) {
        if isOwnProfile {
            composeUsesProfileRecipient = false
            composeAnalyticsSource = source
        } else {
            composeUsesProfileRecipient = true
            composeAnalyticsSource = source
        }
        showCompose = true
    }

    /// Patch embedded author/recipient avatars after a profile photo/name edit.
    private func applyProfileUpdate(_ updated: Profile) {
        for i in sent.indices where sent[i].authorId == updated.id {
            sent[i].author = updated
        }
        for i in received.indices {
            if received[i].authorId == updated.id { received[i].author = updated }
            if received[i].recipientId == updated.id { received[i].recipient = updated }
        }
        for i in inspirations.indices where inspirations[i].user?.id == updated.id {
            inspirations[i].user = updated
        }
    }

    /// Keep Sent/Received in sync when an appreciation is accepted (no pull-to-refresh).
    private func applyAccepted(_ gratitude: Gratitude) {
        guard gratitude.status == .accepted else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if gratitude.recipientId == profile.id,
               !received.contains(where: { $0.id == gratitude.id }) {
                received.insert(gratitude, at: 0)
                received.sort { $0.acceptanceSortDate > $1.acceptanceSortDate }
                stats.received += 1
                if isOwnProfile { section = .received }
            }
            if gratitude.authorId == profile.id,
               !sent.contains(where: { $0.id == gratitude.id }) {
                sent.insert(gratitude, at: 0)
                sent.sort { $0.acceptanceSortDate > $1.acceptanceSortDate }
                stats.sent += 1
                if isOwnProfile {
                    pendingSentCount = max(0, pendingSentCount - 1)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if let url = shownProfile.avatarURL {
                    Button {
                        fullScreenAvatarURL = url
                    } label: {
                        AvatarView(profile: shownProfile, size: 92)
                            .overlay(Circle().strokeBorder(Theme.heartGradient, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View profile photo")
                } else {
                    AvatarView(profile: shownProfile, size: 92)
                        .overlay(Circle().strokeBorder(Theme.heartGradient, lineWidth: 2))
                }
            }

            Text(shownProfile.displayName)
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("@\(shownProfile.username)")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
            if let headline = shownProfile.headline, !headline.isEmpty {
                Text(headline)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if !isOwnProfile {
                Button {
                    composeUsesProfileRecipient = true
                    composeAnalyticsSource = "profile_thank"
                    showCompose = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Thank \(firstName)")
                            .font(Theme.body(14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.coral.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Theme.coral.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityLabel("Thank \(shownProfile.displayName)")
            } else {
                NavigationLink {
                    StatsView()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Your Stats")
                            .font(Theme.body(14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.coral.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Theme.coral.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityLabel("Your Stats")
            }
        }
        .padding(.top, 8)
    }

    // MARK: Nonprofit spotlight

    private var nonprofitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.heartGradient)
                Text(isOwnProfile ? "Cause you champion" : "Cause \(firstName) champions")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.8)
            }

            Text(shownProfile.favoriteNonprofitName ?? "")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if let why = shownProfile.favoriteNonprofitHeadline, !why.isEmpty {
                Text("“\(why)”")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .italic()
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let site = shownProfile.favoriteNonprofitWebsite, let url = URL(string: site) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Learn more")
                            .font(Theme.body(13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.coralLight)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.coral.opacity(0.16),
                                              Theme.surface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.coral.opacity(0.35))
        )
    }

    private var firstName: String {
        shownProfile.fullName?.split(separator: " ").first.map(String.init)
            ?? "@\(shownProfile.username)"
    }

    // MARK: Stats + section switcher (merged)

    private var sectionSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(Array(Section.allCases.enumerated()), id: \.element) { index, s in
                if index > 0 { divider }
                sectionTab(s)
            }
        }
        .padding(.vertical, 6)
        .card()
        .animation(.easeInOut(duration: 0.2), value: section)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1)
            .padding(.vertical, 10)
    }

    private func sectionTab(_ s: Section) -> some View {
        let selected = section == s
        return Button {
            section = s
        } label: {
            VStack(spacing: 5) {
                Text("\(count(for: s))")
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .contentTransition(.numericText())
                Text(s.rawValue)
                    .font(Theme.body(11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.coralLight : Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.coral.opacity(0.12) : .clear)
                    .padding(4)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(selected ? Theme.coral : .clear)
                    .frame(width: 28, height: 2)
                    .padding(.bottom, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.rawValue), \(count(for: s))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func count(for s: Section) -> Int {
        // Prefer the filtered lists so the number matches what's shown
        // (accepted + visibility). Fall back to stats while loading.
        switch s {
        case .sent: return loaded ? sent.count : stats.sent
        case .received: return loaded ? received.count : stats.received
        case .ripple:
            if loaded {
                return inspirations.count + ripplePassOns.count
            }
            return stats.inspired + stats.ripplesPassedOn
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .received:
            gratitudeList(received, empty: "Nothing received yet.")
        case .sent:
            gratitudeList(sent, empty: isOwnProfile
                          ? "You haven't sent an appreciation yet."
                          : "No appreciations sent yet.")
        case .ripple:
            rippleList
        }
    }

    private func gratitudeList(_ list: [Gratitude], empty: String) -> some View {
        VStack(spacing: 12) {
            if list.isEmpty && loaded {
                Text(empty)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 32)
            }
            ForEach(list) { g in
                HStack(alignment: .top, spacing: 12) {
                    ProfileAvatarLink(profile: section == .sent ? g.recipient : g.author, size: 40)
                    NavigationLink(value: g) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rowTitle(for: g))
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                LinkifiedText(
                                    text: g.message,
                                    font: Theme.body(13),
                                    foreground: Theme.textSecondary
                                )
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                if g.visibility == .private {
                                    Label("Private", systemImage: "lock.fill")
                                        .font(Theme.body(11, weight: .medium))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Spacer()
                            if let date = g.displayDate {
                                Text(date, format: .relative(presentation: .named))
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .card()
            }
        }
    }

    private func rowTitle(for g: Gratitude) -> String {
        if section == .sent {
            return isOwnProfile
                ? "You thanked \(g.recipientDisplayName)"
                : "\(shownProfile.displayName) thanked \(g.recipientDisplayName)"
        }
        let author = g.author?.displayName ?? "Someone"
        return isOwnProfile ? "\(author) thanked you"
                            : "\(author) thanked \(shownProfile.displayName)"
    }

    private var rippleList: some View {
        VStack(spacing: 14) {
            if loaded && inspirations.isEmpty && ripplePassOns.isEmpty {
                rippleEmptyState
            } else {
                rippleStoryCard

                rippleSectionHeader("Ripples", count: ripplePassOns.count, systemImage: "water.waves")
                if ripplePassOns.isEmpty {
                    rippleZeroExplainer
                } else {
                    ForEach(ripplePassOns) { child in
                        HStack(alignment: .top, spacing: 12) {
                            ProfileAvatarLink(profile: child.author, size: 40)
                            NavigationLink(value: child) {
                                ripplePassOnRow(child)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .card()
                    }
                    if isOwnProfile {
                        rippleKeepGoingCTA
                    }
                }

                if !inspirations.isEmpty {
                    rippleSectionHeader("Inspired", count: inspirations.count, systemImage: "heart.fill")
                    ForEach(inspirations) { ins in
                        HStack(alignment: .top, spacing: 12) {
                            ProfileAvatarLink(profile: ins.user, size: 40)
                            Group {
                                if let g = ins.gratitude {
                                    NavigationLink(value: g) { inspirationRow(ins) }
                                        .buttonStyle(.plain)
                                } else {
                                    inspirationRow(ins)
                                }
                            }
                        }
                        .padding(14)
                        .card()
                    }
                }
            }
        }
    }

    /// Compact intro — story + chips, no tall empty hero.
    private var rippleStoryCard: some View {
        let inspiredCount = inspirations.count
        let rippleCount = ripplePassOns.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    GratitudeRipple(trigger: loaded, size: 44)
                    Image(systemName: "water.waves")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                .frame(width: 44, height: 44)

                Text("Your gratitude can inspire others")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                rippleChip(value: rippleCount, label: rippleCount == 1 ? "ripple" : "ripples", systemImage: "water.waves")
                rippleChip(value: inspiredCount, label: "inspired", systemImage: "heart.fill")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.coral.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.coral.opacity(0.18), lineWidth: 1)
        )
    }

    private func rippleChip(value: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.coral)
            Text("\(value)")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func rippleSectionHeader(_ title: String, count: Int, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.coral)
            Text(title)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("\(count)")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count)")
    }

    /// Shown when there are zero ripples — explains the idea + invites action.
    private var rippleZeroExplainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isOwnProfile ? "What’s a ripple?" : "No ripples yet")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(isOwnProfile
                 ? "A ripple is when someone receives thanks and then thanks someone new. That next appreciation carries the chain forward — one kind act becoming many."
                 : "Ripples show up when thanks linked to \(firstName) inspire someone to thank someone new. It’s gratitude traveling person to person.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openComposeFromRipple(source: isOwnProfile ? "profile_ripple_zero" : "profile_ripple_zero_thank")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isOwnProfile ? "Start a ripple — thank someone" : "Thank \(firstName)")
                        .font(Theme.body(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Theme.ctaGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(isOwnProfile ? "Start a ripple — thank someone" : "Thank \(shownProfile.displayName)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var rippleKeepGoingCTA: some View {
        Button {
            openComposeFromRipple(source: "profile_ripple_keep_going")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep the ripple going")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Thank someone new — grow the wave.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Keep the ripple going")
    }

    private var rippleEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                GratitudeRipple(trigger: loaded, size: 72)
                Image(systemName: "water.waves")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
            .frame(height: 72)
            .padding(.top, 4)

            Text(isOwnProfile ? "Start your ripple effect" : "No ripple effect yet")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                rippleExplainRow(
                    icon: "water.waves",
                    title: "Ripples",
                    body: "When thanks spark new thanks — kindness passed person to person."
                )
                rippleExplainRow(
                    icon: "heart.fill",
                    title: "Inspired",
                    body: "When someone hearts an appreciation you sent or received."
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            Button {
                openComposeFromRipple(source: isOwnProfile ? "profile_ripple_empty" : "profile_ripple_empty_thank")
            } label: {
                Text(isOwnProfile ? "Send an appreciation" : "Thank \(firstName)")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.ctaGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .accessibilityLabel(isOwnProfile ? "Send an appreciation" : "Thank \(shownProfile.displayName)")
        }
    }

    private func rippleExplainRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .frame(width: 22, height: 22)
                .background(Theme.coral.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(body)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inspirationRow(_ ins: Inspiration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(ins.user?.displayName ?? "Someone")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                 + Text(" was inspired")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary))
                    .multilineTextAlignment(.leading)
                if let message = ins.gratitude?.message {
                    LinkifiedText(
                        text: "“\(message)”",
                        font: Theme.body(13),
                        foreground: Theme.textSecondary
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.coral)
                if let date = ins.createdAt {
                    Text(date, format: .relative(presentation: .named))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func ripplePassOnRow(_ child: Gratitude) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(child.author?.displayName ?? "Someone")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                 + Text(" thanked \(child.recipientDisplayName)")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary))
                    .multilineTextAlignment(.leading)

                LinkifiedText(
                    text: "“\(child.message)”",
                    font: Theme.body(13),
                    foreground: Theme.textSecondary
                )
                .lineLimit(2)
                .multilineTextAlignment(.leading)

                if let parent = child.inspiredByParent {
                    let origin = parent.author?.displayName ?? "someone"
                    Text("from \(origin)’s thanks")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "water.waves")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                if let date = child.displayDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: Data

    private func load() async {
        let viewerId = auth.userId
        do {
            // Own profile: use the already-loaded auth profile; skip a round trip.
            if isOwnProfile {
                freshProfile = auth.currentProfile ?? profile
            } else {
                async let p = GratitudeService.profile(id: profile.id)
                freshProfile = try await p
            }

            async let sentList = GratitudeService.sentBy(userId: profile.id, viewerId: viewerId)
            async let receivedList = GratitudeService.receivedBy(userId: profile.id, viewerId: viewerId)
            async let inspiredList = GratitudeService.inspirations(userId: profile.id, viewerId: viewerId)
            // Soft-fail: missing inspired_by migration / embed must not blank Sent/Received.
            async let rippleList = Result {
                try await GratitudeService.ripples(userId: profile.id, viewerId: viewerId)
            }
            // Accurate counts via head queries (lists are capped).
            async let statsTask = GratitudeService.stats(userId: profile.id)

            let (sentResult, receivedResult, inspiredResult, rippleOutcome, statsResult) =
                try await (sentList, receivedList, inspiredList, rippleList, statsTask)
            let rippleResult = (try? rippleOutcome.get()) ?? []
            var pendingResult = 0
            if isOwnProfile, let userId = auth.userId {
                pendingResult = (try? await GratitudeService.pendingCount(authorId: userId)) ?? pendingSentCount
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                sent = sentResult
                received = receivedResult
                inspirations = inspiredResult
                ripplePassOns = rippleResult
                stats = statsResult
                if isOwnProfile { pendingSentCount = pendingResult }
            }
            if isOwnProfile, let userId = auth.userId {
                await WidgetSnapshotRefresher.refresh(
                    displayName: (freshProfile ?? profile).displayName,
                    userId: userId,
                    email: auth.currentProfile?.email,
                    phone: auth.currentProfile?.phone
                )
            }
        } catch {
            if error.isCancellation { /* keep existing content */ }
        }
        loaded = true
    }
}
