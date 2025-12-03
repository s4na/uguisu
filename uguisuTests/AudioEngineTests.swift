import XCTest
@testable import uguisu

final class AudioEngineTests: XCTestCase {

    func testAudioEngineInitialization() {
        let engine = AudioEngine()
        XCTAssertNotNil(engine)
    }

    func testSampleRateConstant() {
        XCTAssertEqual(AudioEngine.sampleRate, 16000.0)
    }

    func testMaxRecordingDurationConstant() {
        XCTAssertEqual(AudioEngine.maxRecordingDuration, 60.0)
    }

    func testWarningDurationConstant() {
        XCTAssertEqual(AudioEngine.warningDuration, 50.0)
    }

    func testInitialRecordingDuration() {
        let engine = AudioEngine()
        XCTAssertEqual(engine.currentRecordingDuration, 0.0)
    }
}

// MARK: - AudioEngineError Tests

final class AudioEngineErrorTests: XCTestCase {

    func testMicrophonePermissionDeniedError() {
        let error = AudioEngineError.microphonePermissionDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Microphone permission"))
    }

    func testAudioSessionSetupFailedError() {
        let error = AudioEngineError.audioSessionSetupFailed("Test error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Test error"))
    }

    func testEngineStartFailedError() {
        let error = AudioEngineError.engineStartFailed("Test error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Test error"))
    }

    func testRecordingTimeoutError() {
        let error = AudioEngineError.recordingTimeout
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("maximum time"))
    }
}
