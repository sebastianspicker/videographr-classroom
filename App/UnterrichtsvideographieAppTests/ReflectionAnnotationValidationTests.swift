import SessionCore
import XCTest

@testable import Unterrichtsvideographie

final class ReflectionAnnotationValidationTests: XCTestCase {
    func testTimecodeParserProducesMillisecondsForValidMinuteSecondInput() throws {
        XCTAssertEqual(try ReflectionAnnotationTimecode.parse("02:14").get(), 134_000)
        XCTAssertEqual(try ReflectionAnnotationTimecode.parse("0:00").get(), 0)
    }

    func testTimecodeParserRejectsInvalidSecondsAndOverflow() {
        XCTAssertEqual(
            ReflectionAnnotationTimecode.parse("02:60"),
            .failure(.invalidFormat)
        )
        XCTAssertEqual(
            ReflectionAnnotationTimecode.parse("999999999999999999:00"),
            .failure(.outOfRange)
        )
    }

    // Quick links and the editor share this admission, so neither can skip a check.

    func testAdmissionRequiresCurrentLocalReflectionAuthority() {
        var request = Self.validRequest()
        request.authorizesLocalReflection = false
        XCTAssertEqual(Self.rejection(request), .localReflectionNotAuthorized)
    }

    func testAdmissionRequiresKnownDurationAuthorAndNote() {
        var request = Self.validRequest()
        request.durationMilliseconds = nil
        XCTAssertEqual(Self.rejection(request), .durationPending)

        request = Self.validRequest()
        request.author = "  \n"
        XCTAssertEqual(Self.rejection(request), .missingAuthor)
        XCTAssertEqual(Self.rejection(request)?.focus, .author)

        request = Self.validRequest()
        request.note = " "
        XCTAssertEqual(Self.rejection(request), .missingNote)
        XCTAssertEqual(Self.rejection(request)?.focus, .note)
    }

    func testAdmissionBoundsTheIntervalByOrderAndKnownDuration() {
        var request = Self.validRequest()
        request.start = .success(20_000)
        request.end = .success(10_000)
        XCTAssertEqual(Self.rejection(request), .startAfterEnd)

        request = Self.validRequest()
        request.end = .success(60_001)
        XCTAssertEqual(Self.rejection(request), .outsideKnownDuration)

        request = Self.validRequest()
        request.start = .failure(.invalidFormat)
        XCTAssertEqual(Self.rejection(request), .invalidInterval(focus: .start, outOfRange: false))

        request = Self.validRequest()
        request.end = .failure(.outOfRange)
        XCTAssertEqual(Self.rejection(request), .invalidInterval(focus: .end, outOfRange: true))
    }

    func testAdmissionAcceptsWholeVideoLinkWithTheEnteredAuthorAndNote() throws {
        var request = Self.validRequest()
        request.start = .success(0)
        request.end = .success(0)
        request.author = " OP-1 "
        request.note = " Beobachtung "
        let values = try ReflectionAnnotationAdmission.admit(request).get()
        XCTAssertEqual(values.promptIdentifier, request.prompt.rawValue)
        XCTAssertEqual(values.mediaAssetID, request.mediaAssetID)
        XCTAssertEqual(values.startMilliseconds, 0)
        XCTAssertEqual(values.endMilliseconds, 0)
        XCTAssertEqual(values.authorPseudonym, "OP-1")
        XCTAssertEqual(values.note, "Beobachtung")
    }

    private static func validRequest() -> ReflectionAnnotationAdmission.Request {
        ReflectionAnnotationAdmission.Request(
            prompt: ReflectionPromptID.allCases[0],
            mediaAssetID: UUID(),
            authorizesLocalReflection: true,
            durationMilliseconds: 60_000,
            author: "OP-1",
            note: "Beobachtung",
            start: .success(10_000),
            end: .success(20_000)
        )
    }

    private static func rejection(
        _ request: ReflectionAnnotationAdmission.Request
    ) -> ReflectionAnnotationAdmission.Rejection? {
        if case .failure(let rejection) = ReflectionAnnotationAdmission.admit(request) { return rejection }
        return nil
    }
}
