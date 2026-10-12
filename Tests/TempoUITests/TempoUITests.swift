import XCTest

final class TempoUITests: XCTestCase {
  @MainActor func testEmptyStatesAndTabs() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Your baseline is still building."].exists)
    XCTAssertTrue(app.staticTexts["tempo-brand-name"].exists)
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

extension TempoUITests {
  @MainActor func testCaptureProductScreenshots() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)
    wait(for: [ready], timeout: 30)
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    capture("today-light-demo")
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.buttons["Start Padel"].waitForExistence(timeout: 5))
    capture("activity-demo")
    app.buttons["Start Padel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    capture("workout-demo")
    app.buttons["Finish"].tap()
    app.tabBars.buttons["Trends"].tap()
    XCTAssertTrue(app.staticTexts["Personal patterns"].waitForExistence(timeout: 5))
    capture("trends-demo")
    app.tabBars.buttons["Today"].tap()
    app.buttons["See inputs and calculation"].tap()
    XCTAssertTrue(app.navigationBars["Readiness explained"].waitForExistence(timeout: 5))
    capture("readiness-demo")
    app.navigationBars.buttons.firstMatch.tap()
    settings.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    capture("settings-demo")
  }
}

extension TempoUITests {
  @MainActor func testDetectedActivityRequiresConfirmationAndDoesNotRepeat() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--activity-detection-demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.staticTexts["Potential workout"].waitForExistence(timeout: 20))
    app.staticTexts["Potential workout"].tap()
    XCTAssertTrue(app.navigationBars["Review activity"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "detected-activity-demo"
    attachment.lifetime = .keepAlways
    add(attachment)
    for _ in 0..<3 where !app.buttons["Confirm workout"].exists { app.swipeUp() }
    XCTAssertTrue(app.buttons["Confirm workout"].waitForExistence(timeout: 5))
    app.buttons["Confirm workout"].tap()
    XCTAssertTrue(app.staticTexts["Confirmed activity estimate"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Potential workout"].exists)
    app.buttons["Scan recent measurements"].tap()
    XCTAssertFalse(app.staticTexts["Potential workout"].exists)
  }
}
