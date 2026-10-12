import XCTest

final class TempoUITests: XCTestCase {
  @MainActor func testEmptyStatesAndTabs() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Your baseline is still building."].exists)
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.buttons["Start Padel"].waitForExistence(timeout: 5))
    app.buttons["Start Padel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    app.buttons["Finish"].tap()
    app.tabBars.buttons["Trends"].tap()
    XCTAssertTrue(app.staticTexts["No qualifying measurements"].waitForExistence(timeout: 5))
  }
  @MainActor func testSyntheticDemoIsLabeledAndIntegrationsDisabled() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    XCTAssertTrue(
      app.staticTexts["DEMO · Synthetic data · Cloud and Health disabled"].waitForExistence(
        timeout: 15))
    let banner = app.staticTexts["DEMO · Synthetic data · Cloud and Health disabled"]
    let navigation = app.navigationBars["Today"]
    XCTAssertGreaterThanOrEqual(navigation.frame.minY, banner.frame.maxY - 1)
  }
}
