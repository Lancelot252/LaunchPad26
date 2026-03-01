import XCTest

final class MacAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsSearchField() throws {
        let app = XCUIApplication()
        app.launch()

        let searchField = app.textFields["搜索应用或文件夹"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    }

    @MainActor
    func testInlineSettingsPopoverCanOpen() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["打开设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
