import XCTest
@testable import uguisu

final class OverlayWindowControllerTests: XCTestCase {

    func testOverlayWindowControllerInitialization() {
        let controller = OverlayWindowController()

        XCTAssertNotNil(controller)
        XCTAssertNotNil(controller.window)
    }

    func testWindowProperties() {
        let controller = OverlayWindowController()

        guard let window = controller.window else {
            XCTFail("Window should not be nil")
            return
        }

        // Window should be borderless
        XCTAssertTrue(window.styleMask.contains(.borderless))

        // Window should be floating level
        XCTAssertEqual(window.level, .floating)

        // Window should be transparent
        XCTAssertFalse(window.isOpaque)

        // Window should have clear background
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func testWindowSize() {
        let controller = OverlayWindowController()

        guard let window = controller.window else {
            XCTFail("Window should not be nil")
            return
        }

        XCTAssertEqual(window.frame.width, 600)
        XCTAssertEqual(window.frame.height, 200)
    }
}
