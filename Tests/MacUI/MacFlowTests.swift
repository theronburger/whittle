import XCTest

final class MacFlowTests: XCTestCase {
    @MainActor
    func testPairingAndSettingsAreAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let window = app.windows["Whittle"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["copyPairingCode"].exists)
        XCTAssertTrue(app.staticTexts["Fast screen annotation for agentic dev."].exists)
        XCTAssertTrue(app.staticTexts["Updates arrive through TestFlight."].exists)
    }
}
