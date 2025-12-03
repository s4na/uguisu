import XCTest
@testable import uguisu

final class TextInsertionServiceTests: XCTestCase {

    func testSharedInstance() {
        let service1 = TextInsertionService.shared
        let service2 = TextInsertionService.shared
        XCTAssertTrue(service1 === service2, "Should return the same instance")
    }

    func testClearFocus() {
        let service = TextInsertionService.shared
        // Should not crash when clearing focus
        service.clearFocus()
        XCTAssertTrue(true, "clearFocus should not throw")
    }
}

// MARK: - VoiceInputState Tests

final class VoiceInputStateTests: XCTestCase {

    func testReadyStateEquality() {
        let state1 = VoiceInputState.ready
        let state2 = VoiceInputState.ready
        XCTAssertEqual(state1, state2)
    }

    func testRecordingStateEquality() {
        let state1 = VoiceInputState.recording
        let state2 = VoiceInputState.recording
        XCTAssertEqual(state1, state2)
    }

    func testTranscribingStateEquality() {
        let state1 = VoiceInputState.transcribing
        let state2 = VoiceInputState.transcribing
        XCTAssertEqual(state1, state2)
    }

    func testPreviewStateEquality() {
        let state1 = VoiceInputState.preview(text: "Hello")
        let state2 = VoiceInputState.preview(text: "Hello")
        XCTAssertEqual(state1, state2)
    }

    func testPreviewStateInequality() {
        let state1 = VoiceInputState.preview(text: "Hello")
        let state2 = VoiceInputState.preview(text: "World")
        XCTAssertNotEqual(state1, state2)
    }

    func testErrorStateEquality() {
        let state1 = VoiceInputState.error(message: "Error")
        let state2 = VoiceInputState.error(message: "Error")
        XCTAssertEqual(state1, state2)
    }

    func testErrorStateInequality() {
        let state1 = VoiceInputState.error(message: "Error 1")
        let state2 = VoiceInputState.error(message: "Error 2")
        XCTAssertNotEqual(state1, state2)
    }

    func testDifferentStatesInequality() {
        let ready = VoiceInputState.ready
        let recording = VoiceInputState.recording
        XCTAssertNotEqual(ready, recording)
    }
}

// MARK: - OverlayViewModel Tests

final class OverlayViewModelTests: XCTestCase {

    func testInitialState() {
        let viewModel = OverlayViewModel()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertTrue(viewModel.recognizedText.isEmpty)
        XCTAssertEqual(viewModel.audioLevel, 0.0)
        XCTAssertEqual(viewModel.recordingDuration, 0.0)
    }

    func testReset() {
        let viewModel = OverlayViewModel()
        viewModel.recognizedText = "Test"
        viewModel.audioLevel = 0.5
        viewModel.recordingDuration = 10.0

        viewModel.reset()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertTrue(viewModel.recognizedText.isEmpty)
        XCTAssertEqual(viewModel.audioLevel, 0.0)
        XCTAssertEqual(viewModel.recordingDuration, 0.0)
    }
}
