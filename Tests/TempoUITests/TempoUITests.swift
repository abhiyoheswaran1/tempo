import XCTest

final class TempoUITests: XCTestCase {
  @MainActor func testEmptyStatesAndTabs() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Building your baseline"].exists)
    XCTAssertTrue(app.staticTexts["tempo-brand-name"].exists)
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.buttons["Start Padel"].waitForExistence(timeout: 5))
    app.buttons["Start Padel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
    app.buttons["Done"].tap()
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
    XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
    capture("workout-summary-demo")
    app.buttons["Done"].tap()
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

extension TempoUITests {
  @MainActor func testPlacementCanChangeWithoutReplacingBandHistory() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    settings.tap()
    app.buttons["Manage and reconnect bands"].tap()
    app.staticTexts["Synthetic band"].tap()
    app.buttons["Record wearing placement"].tap()
    XCTAssertTrue(app.navigationBars["Wearing placement"].waitForExistence(timeout: 5))
    app.buttons["Now: Wrist"].tap()
    XCTAssertTrue(app.staticTexts["Wrist"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Now: Upper arm / bicep"].tap()
    XCTAssertTrue(app.staticTexts["Upper arm / bicep"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Now: Underwear / WHOOP Body"].tap()
    XCTAssertTrue(app.staticTexts["Underwear / WHOOP Body"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Wrist"].exists)
    XCTAssertTrue(app.staticTexts["Upper arm / bicep"].exists)
  }
}

extension TempoUITests {
  @MainActor func testCompactTodayAndCrossTabWorkoutControls() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    XCTAssertTrue(app.buttons["band-status-control"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["today-sleep-summary"].exists)
    XCTAssertTrue(app.staticTexts["today-movement-summary"].exists)
    XCTAssertLessThan(
      app.staticTexts["today-movement-summary"].frame.maxY, app.tabBars.firstMatch.frame.minY)
    XCTAssertFalse(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'confidence'")).firstMatch
        .exists)
    app.tabBars.buttons["Activity"].tap()
    app.buttons["Start Padel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Trends"].tap()
    XCTAssertTrue(app.buttons["Pause workout"].waitForExistence(timeout: 5))
    app.buttons["Pause workout"].tap()
    XCTAssertTrue(app.buttons["Resume workout"].waitForExistence(timeout: 5))
    app.buttons["Open active workout"].tap()
    XCTAssertTrue(app.navigationBars["Active workout"].waitForExistence(timeout: 5))
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
  }
}

extension TempoUITests {
  @MainActor func testLargeTextDarkModeKeepsPrimaryActionsAccessible() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--large-text", "--dark"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "today-dark-large-text-demo"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertTrue(app.staticTexts["Readiness"].exists)
    for _ in 0..<5 where !app.buttons["band-status-control"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["band-status-control"].exists)
    app.buttons["band-status-control"].tap()
    XCTAssertTrue(app.navigationBars["Band status"].waitForExistence(timeout: 5))
    for _ in 0..<3 where !app.buttons["Manage and reconnect bands"].exists { app.swipeUp() }
    XCTAssertTrue(app.buttons["Manage and reconnect bands"].exists)
  }
}

extension TempoUITests {
  @MainActor func testOlderSleepDoesNotPresentCurrentReadiness() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--stale-sleep-demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    XCTAssertTrue(app.staticTexts["More overnight data needed"].exists)
    XCTAssertTrue(app.staticTexts["Latest sleep"].exists)
    XCTAssertFalse(app.staticTexts["Close to your usual range"].exists)
  }
}

extension TempoUITests {
  @MainActor func testLiveDashboardAndBandManagementKeepDemoHonest() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--live-dashboard-demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    for _ in 0..<3 where !app.buttons["Live dashboard"].isHittable { app.swipeUp() }
    app.buttons["Live dashboard"].tap()
    XCTAssertTrue(app.navigationBars["Live dashboard"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Synthetic demonstration"].exists)
    XCTAssertFalse(app.staticTexts["Receiving live heart rate"].exists)
    let live = XCTAttachment(screenshot: app.screenshot())
    live.name = "live-dashboard-demo"
    live.lifetime = .keepAlways
    add(live)
    for _ in 0..<4 where !app.buttons["Manage bands"].isHittable { app.swipeUp() }
    app.buttons["Manage bands"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic band"].waitForExistence(timeout: 5))
    app.staticTexts["Synthetic band"].tap()
    XCTAssertTrue(app.navigationBars["Synthetic band"].waitForExistence(timeout: 5))
    for _ in 0..<6 where !app.buttons["Disconnect"].exists { app.swipeUp() }
    XCTAssertTrue(app.buttons["Disconnect"].exists)
    for _ in 0..<6 where !app.buttons["Remove band"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["Remove band"].exists)
    app.buttons["Remove band"].tap()
    XCTAssertTrue(app.buttons["confirm-remove-band"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["confirm-remove-band"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Your bands"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Synthetic band"].exists)
  }
}

extension TempoUITests {
  @MainActor func testTodayLiveEntryAndManualRefreshAreProminentAndHonest() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--live-dashboard-demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    let live = app.buttons["Live dashboard"]
    XCTAssertTrue(live.isHittable)
    XCTAssertLessThan(live.frame.minY, app.staticTexts["today-sleep-summary"].frame.minY)
    let refresh = app.buttons["Refresh collection and iCloud"]
    XCTAssertTrue(refresh.isHittable)
    XCTAssertFalse(app.staticTexts["Demo refreshed · real integrations stay off"].exists)
    let scroll = app.scrollViews.firstMatch
    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press(
      forDuration: 0.1,
      thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    XCTAssertTrue(
      app.staticTexts["Demo refreshed · real integrations stay off"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["iCloud synced"].exists)
    // Relaunch gives the button a clean initial state, independent of the pull action.
    app.terminate()
    app.launch()
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    XCTAssertFalse(app.staticTexts["Demo refreshed · real integrations stay off"].exists)
    refresh.tap()
    XCTAssertTrue(
      app.staticTexts["Demo refreshed · real integrations stay off"].waitForExistence(timeout: 10))
    live.tap()
    XCTAssertTrue(app.navigationBars["Live dashboard"].waitForExistence(timeout: 5))
  }
}

extension TempoUITests {
  @MainActor func testAnotherSleepCanBeAddedAfterExistingHistory() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    app.staticTexts["today-sleep-summary"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
    for _ in 0..<4 where !app.buttons["Add another sleep session"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["Add another sleep session"].waitForExistence(timeout: 5))
    app.buttons["Add another sleep session"].tap()
    XCTAssertTrue(app.navigationBars["Record sleep"].waitForExistence(timeout: 5))
    app.buttons["Save"].tap()
    XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Entered'")).firstMatch
        .waitForExistence(timeout: 5))
  }
}
