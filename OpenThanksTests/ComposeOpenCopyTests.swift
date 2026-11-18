import XCTest
#if canImport(ComposeOpenCopy)
@testable import ComposeOpenCopy
#else
@testable import OpenThanks
#endif

final class ComposeOpenCopyTests: XCTestCase {
    func testVariantRawValuesMatchPostHogContract() {
        XCTAssertEqual(ComposeOpenCopy.Variant.control.rawValue, "control")
        XCTAssertEqual(ComposeOpenCopy.Variant.directed.rawValue, "directed")
        XCTAssertEqual(ComposeOpenCopy.Variant.softStart.rawValue, "soft_start")
        XCTAssertEqual(ComposeOpenCopy.experimentKey, "compose_open_copy_v1")
    }

    func testBucketingIsStableForTheSameSeed() {
        let a = ComposeOpenCopy.variantForSeed("user-123")
        let b = ComposeOpenCopy.variantForSeed("user-123")
        XCTAssertEqual(a, b)
    }

    func testBucketingSpreadsAcrossVariants() {
        var seen: Set<ComposeOpenCopy.Variant> = []
        for i in 0..<60 {
            seen.insert(ComposeOpenCopy.variantForSeed("seed-\(i)"))
        }
        XCTAssertEqual(seen.count, 3, "Expected all three variants across seeds")
    }

    func testAssignedVariantPersistsInDefaults() {
        let name = "ComposeOpenCopyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let first = ComposeOpenCopy.assignedVariant(distinctId: "person-a", defaults: defaults)
        let second = ComposeOpenCopy.assignedVariant(distinctId: "person-b", defaults: defaults)
        XCTAssertEqual(first, second, "Sticky assignment must not flip when distinct id changes")
        XCTAssertEqual(defaults.string(forKey: ComposeOpenCopy.variantStorageKey), first.rawValue)
    }

    func testFamilyMapping() {
        XCTAssertNil(ComposeOpenCopy.family(source: "tab_compose", hasCampaign: false, isEditing: true))
        XCTAssertEqual(
            ComposeOpenCopy.family(source: "campaign_home", hasCampaign: false, isEditing: false),
            .campaign
        )
        XCTAssertEqual(
            ComposeOpenCopy.family(source: "tab_compose", hasCampaign: true, isEditing: false),
            .campaign
        )
        XCTAssertEqual(
            ComposeOpenCopy.family(source: "notification_friday", hasCampaign: false, isEditing: false),
            .notification
        )
        XCTAssertEqual(
            ComposeOpenCopy.family(source: "calendar_evening_nudge", hasCampaign: false, isEditing: false),
            .notification
        )
        XCTAssertEqual(
            ComposeOpenCopy.family(source: "tab_compose", hasCampaign: false, isEditing: false),
            .blank
        )
        XCTAssertEqual(
            ComposeOpenCopy.family(source: "home_empty_first_send", hasCampaign: false, isEditing: false),
            .blank
        )
    }

    func testDirectedBlankPackHasReassuranceAndNoSoftStarter() {
        let pack = ComposeOpenCopy.pack(family: .blank, variant: .directed)
        XCTAssertEqual(pack.bannerTitle, "Who made today a little better?")
        XCTAssertEqual(pack.reassurance, ComposeOpenCopy.reassurance)
        XCTAssertNil(pack.softStarter)
        XCTAssertEqual(pack.placeholder, "Thank you for...")
    }

    func testSoftStartPackPrefillsOnlyViaSoftStarter() {
        let pack = ComposeOpenCopy.pack(family: .notification, variant: .softStart)
        XCTAssertEqual(pack.softStarter, "Thank you for — ")
        XCTAssertEqual(pack.reassurance, ComposeOpenCopy.reassurance)
        XCTAssertEqual(pack.bannerTitle, "Who made today a little better?")
    }

    func testCampaignPackKeepsHintOutOfMessageAndAddsReassuranceOnTreatment() {
        let control = ComposeOpenCopy.pack(
            family: .campaign,
            variant: .control,
            campaignHint: "Thank a teammate"
        )
        XCTAssertNil(control.bannerTitle)
        XCTAssertNil(control.reassurance)
        XCTAssertNil(control.softStarter)

        let directed = ComposeOpenCopy.pack(
            family: .campaign,
            variant: .directed,
            campaignHint: "Thank a teammate"
        )
        XCTAssertEqual(directed.reassurance, ComposeOpenCopy.reassurance)
        XCTAssertNil(directed.softStarter)

        let soft = ComposeOpenCopy.pack(
            family: .campaign,
            variant: .softStart,
            campaignHint: "Thank a teammate"
        )
        XCTAssertEqual(soft.softStarter, "Thank you for — ")
    }

    func testCustomPlaceholderIsPreserved() {
        let pack = ComposeOpenCopy.pack(
            family: .blank,
            variant: .control,
            customPlaceholder: "Who helped you this week?"
        )
        XCTAssertEqual(pack.placeholder, "Who helped you this week?")
    }

    func testSoftStarterShouldOnlyApplyWhenMessageEmpty() {
        let starter = ComposeOpenCopy.pack(family: .blank, variant: .softStart).softStarter
        XCTAssertEqual(starter, "Thank you for — ")
        // ComposeView owns the empty-message gate; pack itself always exposes the starter.
        XCTAssertFalse(starter!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
