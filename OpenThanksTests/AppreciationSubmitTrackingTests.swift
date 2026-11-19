import XCTest
#if canImport(AppreciationSubmit)
@testable import AppreciationSubmit
#else
@testable import OpenThanks
#endif

final class AppreciationSubmitTrackingTests: XCTestCase {
    private let jeff = UUID(uuidString: "8DAD3434-1111-4111-8111-111111111111")!
    private let older = UUID(uuidString: "19DA6B6A-2222-4222-8222-222222222222")!

    // MARK: Rule

    func testFirstCreateCounts() {
        XCTAssertEqual(action(.created, jeff, []), .submit)
    }

    func testEditDoesNotCountEvenWhenTheIdWasNeverSubmitted() {
        // Older rows (and notes created on another device) are not in this
        // device's ledger. Re-saving them must still not look like a send.
        XCTAssertEqual(action(.updated, older, []), .edit)
        XCTAssertEqual(action(.updated, jeff, []), .edit)
    }

    func testEditOfAnAlreadyCountedIdStaysAnEdit() {
        XCTAssertEqual(action(.updated, jeff, [jeff]), .edit)
    }

    func testReplayOfTheSameCreateDoesNotCountAgain() {
        XCTAssertEqual(action(.created, jeff, [jeff]), .ignoreDuplicateSubmit)
    }

    func testUUIDSpellingDoesNotOpenASecondCount() {
        let lower = UUID(uuidString: "8dad3434-1111-4111-8111-111111111111")!
        XCTAssertEqual(action(.created, jeff, [lower]), .ignoreDuplicateSubmit)
        XCTAssertEqual(jeff, lower)
    }

    func testQueuedCreateCountsOnceThenEditsDoNot() {
        // Offline / Watch: the insert is the one send. A later phone save of
        // that same row is an edit. A second delivery of the insert is not.
        XCTAssertEqual(action(.created, jeff, []), .submit)
        XCTAssertEqual(action(.created, jeff, [jeff]), .ignoreDuplicateSubmit)
        XCTAssertEqual(action(.updated, jeff, [jeff]), .edit)
    }

    func testADifferentAppreciationStillCounts() {
        XCTAssertEqual(action(.created, older, [jeff]), .submit)
    }

    // MARK: Ledger

    func testLedgerCountsTheFirstCreateOnly() {
        var ledger = makeLedger()
        XCTAssertTrue(ledger.claimCreated(jeff))
        XCTAssertFalse(ledger.claimCreated(jeff))
        XCTAssertFalse(ledger.claimCreated(
            UUID(uuidString: "8dad3434-1111-4111-8111-111111111111")!
        ))
    }

    func testLedgerKeepsTheIdAfterTheMemoryCacheIsDropped() {
        let defaults = makeDefaults()
        var ledger = AppreciationSubmitLedger(defaults: defaults)
        XCTAssertTrue(ledger.claimCreated(jeff))

        var reloaded = AppreciationSubmitLedger(defaults: defaults)
        XCTAssertFalse(reloaded.claimCreated(jeff))
        XCTAssertTrue(reloaded.claimCreated(older))
    }

    func testRepeatedEditsAreNotRecordedAsSends() {
        var ledger = makeLedger()
        // Five saves of one row: the insert claims once; four updates never claim.
        XCTAssertTrue(ledger.claimCreated(jeff))
        for _ in 0..<4 {
            XCTAssertEqual(action(.updated, jeff, [jeff]), .edit)
            XCTAssertFalse(ledger.claimCreated(jeff))
        }
    }

    // MARK: Call sites

    func testComposeEditDoesNotSubmitAndCreateStillDoes() throws {
        let send = try functionBody("send", in: try readSource("OpenThanks/Views/Compose/ComposeView.swift"))
        let branches = try ifElseBodies(startingAt: "if let editing = editingTarget", in: send)
        XCTAssertTrue(branches.then.contains("Analytics.appreciationEdited("))
        XCTAssertFalse(branches.then.contains("Analytics.appreciationSubmitted("))
        XCTAssertTrue(branches.else.contains("Analytics.appreciationSubmitted("))
        XCTAssertFalse(branches.else.contains("Analytics.appreciationEdited("))
        XCTAssertTrue(branches.then.contains("GratitudeService.update("))
        XCTAssertTrue(branches.else.contains("GratitudeService.create("))
    }

    func testSubmitEventClaimsTheIdBeforeCapture() throws {
        let body = try functionBody(
            "appreciationSubmitted",
            in: try readSource("OpenThanks/Services/Analytics.swift")
        )
        let claim = try XCTUnwrap(body.range(of: "AppreciationSubmitTracking.claimCreated(gratitudeId)"))
        let capture = try XCTUnwrap(body.range(of: "capture(\"appreciation_submitted\""))
        XCTAssertLessThan(claim.lowerBound, capture.lowerBound)
        XCTAssertTrue(body.contains("guard AppreciationSubmitTracking.claimCreated(gratitudeId) else { return }"))
    }

    func testEditEventDoesNotClaimASend() throws {
        let body = try functionBody(
            "appreciationEdited",
            in: try readSource("OpenThanks/Services/Analytics.swift")
        )
        XCTAssertTrue(body.contains("capture(\"appreciation_edited\""))
        XCTAssertFalse(body.contains("claimCreated"))
        XCTAssertFalse(body.contains("appreciation_submitted"))
        XCTAssertTrue(body.contains("gratitudeId"))
        XCTAssertTrue(body.contains("source"))
    }

    func testCreateRetriesDoNotTrackInsideTheService() throws {
        let service = try readSource("OpenThanks/Services/GratitudeService.swift")
        XCTAssertFalse(service.contains("appreciationSubmitted"))
        XCTAssertFalse(service.contains("appreciation_submitted"))
        let create = try functionBody("create", in: service)
        XCTAssertTrue(create.contains("recentCreatedMatch"))
        XCTAssertTrue(create.contains("attemptNumber: 2"))
    }

    func testDuplicateTapIsBlockedBeforeTheRequest() throws {
        let send = try functionBody("send", in: try readSource("OpenThanks/Views/Compose/ComposeView.swift"))
        let guardAt = try offset(of: "guard !sending else { return }", in: send)
        let setAt = try offset(of: "sending = true", in: send)
        let guestAwait = try offset(of: "await promptGuestSignInToSave()", in: send)
        let createAwait = try offset(of: "await resolveRecipientBeforeSend()", in: send)
        XCTAssertLessThan(guardAt, setAt)
        XCTAssertLessThan(setAt, guestAwait)
        XCTAssertLessThan(setAt, createAwait)
        let view = try readSource("OpenThanks/Views/Compose/ComposeView.swift")
        XCTAssertTrue(view.contains(".disabled(sending || (!needsDisplayName && !canSend))"))
    }

    func testWatchInsertStillSubmitsAndDeliverUpdatesDoNot() throws {
        let voice = try readSource("OpenThanks/Services/WatchVoiceDraftStore.swift")
        XCTAssertEqual(voice.components(separatedBy: "Analytics.appreciationSubmitted(").count - 1, 2)
        XCTAssertFalse(voice.contains("appreciationEdited"))

        let watch = try readSource("OpenThanks/Services/WatchConnectivityService.swift")
        let handleCreate = try functionBody("handleCreate", in: watch)
        XCTAssertTrue(handleCreate.contains("GratitudeService.create"))
        XCTAssertTrue(handleCreate.contains("Analytics.appreciationSubmitted("))
        XCTAssertFalse(handleCreate.contains("appreciationEdited"))

        let deliver = try readSource("OpenThanks/Views/Compose/DeliverAppreciationView.swift")
        XCTAssertTrue(deliver.contains("GratitudeService.update("))
        XCTAssertFalse(deliver.contains("appreciationSubmitted"))
        XCTAssertFalse(deliver.contains("appreciation_submitted"))
    }

    func testPendingEditOpensTheExistingRow() throws {
        let settings = try readSource("OpenThanks/Views/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("analyticsSource: \"edit_pending\""))
        XCTAssertTrue(settings.contains("editing: g"))
    }

    // MARK: Helpers

    private func action(
        _ kind: AppreciationSaveKind,
        _ id: UUID,
        _ previous: Set<UUID>
    ) -> AppreciationSaveAnalytics {
        AppreciationSubmitTracking.action(
            kind: kind,
            gratitudeId: id,
            previouslySubmitted: previous
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppreciationSubmitTrackingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeLedger() -> AppreciationSubmitLedger {
        AppreciationSubmitLedger(defaults: makeDefaults())
    }

    private func offset(of needle: String, in source: String) throws -> Int {
        guard let range = source.range(of: needle) else {
            throw AppreciationSubmitTrackingTestError("Missing \(needle)")
        }
        return source.distance(from: source.startIndex, to: range.lowerBound)
    }

    private func readSource(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func functionBody(_ name: String, in source: String) throws -> String {
        let marker = "func \(name)("
        guard let start = source.range(of: marker),
              let brace = source[start.upperBound...].firstIndex(of: "{")
        else {
            throw AppreciationSubmitTrackingTestError("Missing function \(name)")
        }
        return try balancedBody(in: source, openBrace: brace)
    }

    private func ifElseBodies(
        startingAt marker: String,
        in source: String
    ) throws -> (then: String, else: String) {
        guard let start = source.range(of: marker),
              let brace = source[start.upperBound...].firstIndex(of: "{")
        else {
            throw AppreciationSubmitTrackingTestError("Missing \(marker)")
        }
        let thenEnd = try balancedEnd(in: source, openBrace: brace)
        let then = String(source[source.index(after: brace)..<thenEnd])
        var index = source.index(after: thenEnd)
        while index < source.endIndex, source[index].isWhitespace { index = source.index(after: index) }
        let rest = source[index...]
        guard rest.hasPrefix("else") else {
            throw AppreciationSubmitTrackingTestError("Missing else after \(marker)")
        }
        guard let elseBrace = rest.firstIndex(of: "{") else {
            throw AppreciationSubmitTrackingTestError("Missing else brace")
        }
        let elseBody = try balancedBody(in: source, openBrace: elseBrace)
        return (then, elseBody)
    }

    private func balancedBody(in source: String, openBrace: String.Index) throws -> String {
        let end = try balancedEnd(in: source, openBrace: openBrace)
        return String(source[source.index(after: openBrace)..<end])
    }

    private func balancedEnd(in source: String, openBrace: String.Index) throws -> String.Index {
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        throw AppreciationSubmitTrackingTestError("Unbalanced braces")
    }
}

private struct AppreciationSubmitTrackingTestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
