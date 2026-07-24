import SwiftUI

/// Avatar stack + “Alex and 3 others” summary that opens a sheet of everyone
/// who hearted the appreciation — mirrors the web `HeartedBy` component.
struct HeartedByView: View {
    let gratitudeId: UUID
    var heartCount: Int

    @State private var hearters: [Profile] = []
    @State private var resolvedCount = 0
    @State private var loaded = false
    @State private var showList = false

    private var displayCount: Int { max(heartCount, resolvedCount) }

    var body: some View {
        Group {
            if displayCount > 0 {
                Button {
                    showList = true
                } label: {
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .task(id: "\(gratitudeId.uuidString)-\(heartCount)") {
            await load()
        }
        .sheet(isPresented: $showList) {
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
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(hearters) { person in
                                NavigationLink(value: person) {
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
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, 76)
                            }

                            if displayCount > hearters.count {
                                Text("and \(displayCount - hearters.count) more")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
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
