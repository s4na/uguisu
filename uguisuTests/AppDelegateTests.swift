import XCTest
@testable import uguisu

final class AppDelegateTests: XCTestCase {

    func testAppDelegateInitialization() {
        let appDelegate = AppDelegate()
        XCTAssertNotNil(appDelegate)
    }
}
