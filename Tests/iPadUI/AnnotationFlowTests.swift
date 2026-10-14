import XCTest
import WhittleCore

final class AnnotationFlowTests: XCTestCase {
    @MainActor
    func testPairingCodeWorksWithoutOpeningCamera() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["connectionSettings"].tap()
        let ticket = try PairingTicket(name: "Code-paired Mac", hosts: ["127.0.0.1"])
        let codeField = app.descendants(matching: .any).matching(identifier: "pairingCode").firstMatch
        codeField.tap()
        codeField.typeText(ticket.code)
        app.buttons["pairMac"].tap()
        app.buttons["connectionSettings"].tap()
        XCTAssertTrue(app.staticTexts["Code-paired Mac"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Scan Your Mac’s Code"].exists)
    }

    @MainActor
    func testDragNoteEditAndQueueFeedback() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let canvas = app.otherElements["annotationCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let note = app.images["dragNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        let editor = app.textViews["noteTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Increase the spacing above this card.")
        app.buttons["finishNote"].tap()
        XCTAssertTrue(app.staticTexts["annotationSummary"].label.contains("1 notes"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Workspace with an anchored note"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["copyFeedback"].tap()
        XCTAssertTrue(app.staticTexts["copyStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["copyStatus"].label.contains("Queued"))
    }

    @MainActor
    func testArrowAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let canvas = app.otherElements["annotationCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["tool-arrow"].tap()
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue((canvas.value as? String)?.contains("1 arrows") == true)
        app.buttons["undo"].tap()
        XCTAssertTrue((canvas.value as? String)?.contains("0 arrows") == true)
        app.buttons["resetViewport"].tap()
    }
}
