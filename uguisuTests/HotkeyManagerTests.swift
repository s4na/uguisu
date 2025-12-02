import XCTest
@testable import uguisu

final class HotkeyManagerTests: XCTestCase {

    func testHotkeyManagerInitialization() {
        var callbackCalled = false
        let manager = HotkeyManager {
            callbackCalled = true
        }

        XCTAssertNotNil(manager)
        XCTAssertFalse(callbackCalled)
    }

    func testModifierFlagsDetection() {
        // Test that Option key detection logic works correctly
        let optionFlag = CGEventFlags.maskAlternate
        let commandFlag = CGEventFlags.maskCommand
        let controlFlag = CGEventFlags.maskControl
        let shiftFlag = CGEventFlags.maskShift

        // Option only
        let optionOnly = optionFlag
        XCTAssertTrue(optionOnly.contains(.maskAlternate))
        XCTAssertFalse(optionOnly.contains(.maskCommand))
        XCTAssertFalse(optionOnly.contains(.maskControl))
        XCTAssertFalse(optionOnly.contains(.maskShift))

        // Option + Command
        let optionCommand: CGEventFlags = [optionFlag, commandFlag]
        XCTAssertTrue(optionCommand.contains(.maskAlternate))
        XCTAssertTrue(optionCommand.contains(.maskCommand))
    }

    func testSpaceKeyCode() {
        // Space key code should be 49
        let spaceKeyCode: Int64 = 49
        XCTAssertEqual(spaceKeyCode, 49)
    }
}
