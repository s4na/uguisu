import XCTest
@testable import uguisu

final class STTEngineTests: XCTestCase {

    func testSTTEngineInitialization() {
        let engine = STTEngine()
        XCTAssertNotNil(engine)
    }

    func testDefaultLocale() {
        let engine = STTEngine()
        XCTAssertEqual(engine.locale.identifier, "ja-JP")
    }

    func testLocaleChange() {
        let engine = STTEngine()
        engine.locale = Locale(identifier: "en-US")
        XCTAssertEqual(engine.locale.identifier, "en-US")
    }
}

// MARK: - STTEngineError Tests

final class STTEngineErrorTests: XCTestCase {

    func testPermissionDeniedError() {
        let error = STTEngineError.speechRecognitionPermissionDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("permission"))
    }

    func testNotAvailableError() {
        let error = STTEngineError.speechRecognitionNotAvailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not available"))
    }

    func testRecognitionFailedError() {
        let error = STTEngineError.recognitionFailed("Test error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Test error"))
    }

    func testNoSpeechDetectedError() {
        let error = STTEngineError.noSpeechDetected
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("No speech"))
    }
}
