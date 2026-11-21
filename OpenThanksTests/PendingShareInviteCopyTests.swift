import XCTest
#if canImport(PendingShareInviteCopy)
@testable import PendingShareInviteCopy
#else
@testable import OpenThanks
#endif

final class PendingShareInviteCopyTests: XCTestCase {
    func testSpanishInviteMatchesMessageLanguage() {
        let language = PendingShareInviteCopy.Language.detect(
            from: "Gracias Ana por ayudarme tanto esta semana con el proyecto."
        )
        XCTAssertEqual(language, .spanish)
        let caption = PendingShareInviteCopy.inviteCaption(
            firstName: "Ana",
            preview: "Gracias Ana por ayudarme",
            isPrivate: false,
            language: .spanish
        )
        XCTAssertTrue(caption.contains("¡Hola Ana!"))
        XCTAssertTrue(caption.contains("agradecimiento"))
        XCTAssertTrue(caption.localizedCaseInsensitiveContains("aquí"))
    }

    func testEnglishFallbackForShortOrAmbiguousText() {
        XCTAssertEqual(
            PendingShareInviteCopy.Language.detect(from: "Thanks!"),
            .english
        )
    }

    func testRomanianSubject() {
        let subject = PendingShareInviteCopy.emailSubject(isPrivate: true, language: .romanian)
        XCTAssertTrue(subject.localizedCaseInsensitiveContains("privată"))
    }

    func testDetectionIsComputedFromMessageAtShareTime() {
        // Pending share and post-create share both call Language.detect(from: message)
        // on the current note — there is no create-time-only cache.
        let spanish = PendingShareInviteCopy.Language.detect(
            from: "Muchas gracias por tu ayuda con la presentación de hoy."
        )
        let french = PendingShareInviteCopy.Language.detect(
            from: "Merci beaucoup pour ton aide précieuse cette semaine."
        )
        XCTAssertEqual(spanish, .spanish)
        XCTAssertEqual(french, .french)
    }
}
