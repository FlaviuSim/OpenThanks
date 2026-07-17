import SwiftUI

/// Own-profile tab: your profile plus the settings entry point.
struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
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
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .syncAppAppearance()
            }
            .appDestinations()
            .syncAppAppearance()
        }
    }
}

/// Any user's profile: header, nonprofit spotlight, stats, and
/// Sent / Received / Inspired — accepted posts only, private posts shown
/// only to the people involved in them.
struct UserProfileView: View {
    enum Section: String, CaseIterable {
        case sent = "Sent", received = "Received", inspired = "Inspired"
    }

    let profile: Profile
    @Environment(AuthService.self) private var auth

    @State private var freshProfile: Profile?
    @State private var section: Section = .sent
    @State private var stats = ProfileStats()
    @State private var sent: [Gratitude] = []
    @State private var received: [Gratitude] = []
    @State private var inspirations: [Inspiration] = []
    @State private var loaded = false

    private var shownProfile: Profile { freshProfile ?? profile }
    private var isOwnProfile: Bool { auth.userId == profile.id }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if shownProfile.favoriteNonprofitName != nil { nonprofitCard }
                sectionSwitcher
                sectionContent
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 96)
        }
        .background(Theme.background)
        .navigationTitle(isOwnProfile ? "Profile" : shownProfile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.currentProfile?.id == profile.id ? auth.currentProfile : profile) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(profile: shownProfile, size: 92)
                .overlay(Circle().strokeBorder(Theme.heartGradient, lineWidth: 2))
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
        .padding(.vertical, 4)
        .card()
        .animation(.easeInOut(duration: 0.2), value: section)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 44)
    }

    private func sectionTab(_ s: Section) -> some View {
        let selected = section == s
        return Button {
            section = s
        } label: {
            VStack(spacing: 4) {
                Text("\(count(for: s))")
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .contentTransition(.numericText())
                Text(s.rawValue)
                    .font(Theme.body(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.coralLight : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.coral.opacity(0.12) : .clear)
                    .padding(4)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(selected ? Theme.coral : .clear)
                    .frame(width: 28, height: 2)
                    .padding(.bottom, 6)
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
        case .inspired: return loaded ? inspirations.count : stats.inspired
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .sent:
            gratitudeList(sent, empty: isOwnProfile
                          ? "You haven't sent an appreciation yet."
                          : "No appreciations sent yet.")
        case .received:
            gratitudeList(received, empty: "Nothing received yet.")
        case .inspired:
            inspiredList
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
                                Text(g.message)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if g.visibility == .private {
                                    Label("Private", systemImage: "lock.fill")
                                        .font(Theme.body(11, weight: .medium))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Spacer()
                            if let date = g.createdAt {
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

    private var inspiredList: some View {
        VStack(spacing: 12) {
            if inspirations.isEmpty && loaded {
                Text(isOwnProfile
                     ? "When someone hearts an appreciation you sent or received, they'll show up here."
                     : "No one has been inspired yet — be the first.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 16)
            }
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
                    Text("“\(message)”")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
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

    // MARK: Data

    private func load() async {
        let viewerId = auth.userId
        do {
            async let p = GratitudeService.profile(id: profile.id)
            async let s = GratitudeService.stats(userId: profile.id)
            async let sentList = GratitudeService.sentBy(userId: profile.id, viewerId: viewerId)
            async let receivedList = GratitudeService.receivedBy(userId: profile.id, viewerId: viewerId)
            async let inspiredList = GratitudeService.inspirations(userId: profile.id, viewerId: viewerId)
            let (profileResult, statsResult, sentResult, receivedResult, inspiredResult) =
                try await (p, s, sentList, receivedList, inspiredList)
            freshProfile = profileResult
            stats = statsResult
            sent = sentResult
            received = receivedResult
            inspirations = inspiredResult
        } catch {
            if error.isCancellation { /* keep existing content */ }
        }
        loaded = true
    }
}
