import XCTest

final class TempoUITests: XCTestCase {
  @MainActor func testPossibleSleepRequiresReviewAndConfirmation() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--sleep-candidate-demo"]
    app.launch()
    let review = app.buttons["review-possible-sleep"]
    XCTAssertTrue(review.waitForExistence(timeout: 25))
    for _ in 0..<4 where !review.isHittable { app.swipeUp() }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "possible-sleep-demo"; attachment.lifetime = .keepAlways; add(attachment)
    review.tap()
    XCTAssertTrue(app.navigationBars["Review possible sleep"].waitForExistence(timeout: 5))
    app.buttons["Save"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["today-sleep-summary"].firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["review-possible-sleep"].exists)
  }
  @MainActor func testSettingsAndReportedBatteryHaveSeparateMeaning() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo", "--battery-ui-demo"]
    app.launch()
    XCTAssertTrue(app.buttons["tempo-settings"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["today-battery-percent"].exists)
    XCTAssertEqual(app.staticTexts["today-battery-percent"].label, "73%")
    XCTAssertFalse(app.descendants(matching: .any)["today-header-battery-percent"].exists)
    XCTAssertTrue(app.staticTexts["today-battery-percent"].isHittable)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "today-battery-demo"; shot.lifetime = .keepAlways; add(shot)
    app.buttons["tempo-settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
  }
  @MainActor func testEmptyStatesAndTabs() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Building your baseline"].exists)
    XCTAssertTrue(app.staticTexts["tempo-brand-name"].exists)
    XCTAssertTrue(app.staticTexts["today-history-unavailable"].exists)
    XCTAssertTrue(app.staticTexts["sleep-collection-explanation"].exists)
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.buttons["Start Padel"].waitForExistence(timeout: 5))
    app.buttons["Start Padel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.buttons["confirm-finish-workout"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["confirm-finish-workout"].firstMatch.tap()
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
    app.buttons["today-journal-check-in"].tap()
    XCTAssertTrue(app.navigationBars["Your journal"].waitForExistence(timeout: 5))
    capture("journal-demo")
    app.buttons["Cancel"].tap()
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.buttons["Start Padel"].waitForExistence(timeout: 5))
    capture("activity-demo")
    app.buttons["Start Padel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    capture("workout-demo")
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.buttons["confirm-finish-workout"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["confirm-finish-workout"].firstMatch.tap()
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
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'registered-band-'")).firstMatch
      .tap()
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
    XCTAssertTrue(app.buttons["confirm-finish-workout"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["confirm-finish-workout"].firstMatch.tap()
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
    XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Readiness"].waitForExistence(timeout: 5))
    // Allow native large-title/layout presentation to settle before recording the real frame.
    Thread.sleep(forTimeInterval: 1)
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
    XCTAssertTrue(app.segmentedControls.buttons["4 hours"].isSelected)
    XCTAssertTrue(app.staticTexts["live-history-coverage"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["live-received-time"].exists)
    XCTAssertTrue(app.staticTexts["live-history-completeness"].exists)
    XCTAssertFalse(app.staticTexts["Chart retains recorded highs and lows. Average uses all covered readings, not plotted points."].exists)
    XCTAssertFalse(app.staticTexts["Receiving live heart rate"].exists)
    let live = XCTAttachment(screenshot: app.screenshot())
    live.name = "live-dashboard-demo"
    live.lifetime = .keepAlways
    add(live)
    app.segmentedControls.buttons["15 min"].tap()
    XCTAssertTrue(app.segmentedControls.buttons["15 min"].isSelected)
    XCTAssertTrue(app.staticTexts["live-history-coverage"].waitForExistence(timeout: 10))
    let evidence = app.buttons["Source and measurement evidence"]
    for _ in 0..<4 where !evidence.isHittable { app.swipeUp() }
    XCTAssertTrue(evidence.isHittable)
    evidence.tap()
    XCTAssertTrue(app.staticTexts["Intervals are not an overnight HRV result."].exists)
    for _ in 0..<4 where !app.buttons["Manage bands"].isHittable { app.swipeUp() }
    app.buttons["Manage bands"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic band"].waitForExistence(timeout: 5))
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'registered-band-'")).firstMatch
      .tap()
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
    app.navigationBars["Your bands"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Live dashboard"].waitForExistence(timeout: 5))
    for _ in 0..<5 where !app.staticTexts["Waiting for a heart-rate measurement"].isHittable {
      app.swipeDown()
    }
    XCTAssertTrue(app.staticTexts["Waiting for a heart-rate measurement"].exists)
    XCTAssertTrue(app.staticTexts["No recent readings"].exists)
    app.tabBars.buttons["Trends"].tap()
    let calculation = app.buttons["Source and calculation"]
    for _ in 0..<4 where !calculation.isHittable { app.swipeUp() }
    XCTAssertTrue(calculation.isHittable)
    calculation.tap()
    XCTAssertTrue(app.staticTexts["Synthetic band · archived"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["trend-selected-value"].exists)
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
    // Start below the expanded native navigation title, inside scrollable content.
    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).press(
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

extension TempoUITests {
  @MainActor func testActivitySelectionAndCancelableFinish() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 15))
    app.tabBars.buttons["Activity"].tap()
    XCTAssertTrue(app.buttons["Running"].isHittable)
    app.buttons["Running"].tap()
    app.buttons["Start Running"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      (app.staticTexts["Active workout duration"].value as? String)?.contains(":") == true)
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.buttons["confirm-finish-workout"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Pause"].exists)
    XCTAssertFalse(app.navigationBars["Workout summary"].exists)
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    app.buttons["Resume"].tap()
    app.buttons["Finish"].tap()
    app.buttons["confirm-finish-workout"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
  }
}

extension TempoUITests {
  @MainActor func testBaselineBuildingShowsCollectionBeforeCompactProgress() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    let live = app.buttons["Live dashboard"]
    XCTAssertTrue(live.waitForExistence(timeout: 15))
    let progress = app.staticTexts["baseline-progress"].firstMatch
    XCTAssertTrue(progress.waitForExistence(timeout: 5))
    XCTAssertLessThan(live.frame.minY, progress.frame.minY)
    XCTAssertFalse(app.staticTexts["Readiness unavailable"].exists)
    XCTAssertTrue(app.buttons["See inputs and calculation"].exists)
    let today = XCTAttachment(screenshot: app.screenshot())
    today.name = "today-baseline-empty"
    today.lifetime = .keepAlways
    add(today)
    app.buttons["band-status-control"].tap()
    for _ in 0..<3 where !app.staticTexts["Band history retrieval"].exists { app.swipeUp() }
    XCTAssertTrue(app.staticTexts["Band history retrieval"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "Connect a band to check support")
      ).firstMatch.exists)
    for _ in 0..<3 where !app.buttons["Manage and reconnect bands"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["Manage and reconnect bands"].isHittable)
    let status = XCTAttachment(screenshot: app.screenshot())
    status.name = "band-status-empty"
    status.lifetime = .keepAlways
    add(status)
  }
  @MainActor func testTrendsSelectsOneMetricAndAccessibleDayEvidence() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    app.tabBars.buttons["Trends"].tap()
    XCTAssertTrue(app.buttons["Measurement"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Sleep duration"].exists)
    app.buttons["Daily values and evidence"].tap()
    let day = app.buttons["trend-day-0"]
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    day.tap()
    XCTAssertTrue(app.staticTexts["trend-selected-value"].exists)
    app.buttons["Measurement"].tap()
    app.buttons["Sleep duration"].tap()
    XCTAssertTrue(app.staticTexts["Sleep duration"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.staticTexts["Average during measured periods, not an all-day or resting heart rate."]
        .exists)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "sleep-trends-demo"
    shot.lifetime = .keepAlways
    add(shot)
  }
}

extension TempoUITests {
  @MainActor func testLargeTextTrendsAndLiveKeepEvidenceReachable() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "--demo", "--live-dashboard-demo", "--large-text", "--dark",
    ]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    app.tabBars.buttons["Trends"].tap()
    XCTAssertTrue(app.buttons["Measurement"].isHittable)
    let daily = app.buttons["Daily values and evidence"]
    for _ in 0..<6 where !daily.isHittable { app.swipeUp() }
    XCTAssertTrue(daily.isHittable)
    daily.tap()
    let row = app.buttons["trend-day-0"]
    for _ in 0..<4 where !row.isHittable { app.swipeUp() }
    XCTAssertTrue(row.isHittable)
    row.tap()
    XCTAssertTrue(app.staticTexts["trend-selected-value"].exists)
    app.tabBars.buttons["Today"].tap()
    let live = app.buttons["Live dashboard"]
    for _ in 0..<6 where !live.isHittable { app.swipeUp() }
    XCTAssertTrue(live.isHittable)
    live.tap()
    let evidence = app.buttons["Source and measurement evidence"]
    for _ in 0..<6 where !evidence.isHittable { app.swipeUp() }
    XCTAssertTrue(evidence.isHittable)
    evidence.tap()
    for _ in 0..<4 where !app.buttons["Manage bands"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["Manage bands"].isHittable)
  }
}

extension TempoUITests {
  @MainActor func testSettingsProvidesExplicitBandHistoryEntry() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    settings.tap()
    let entry = app.buttons["Band status and history"]
    XCTAssertTrue(entry.waitForExistence(timeout: 3))
    guard entry.exists else { return }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "settings-demo"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    entry.tap()
    XCTAssertTrue(app.navigationBars["Band status"].waitForExistence(timeout: 5))
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Band history retrieval"].exists)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Unavailable in demo"))
        .firstMatch.exists)
  }
}

extension TempoUITests {
  @MainActor func testJournalQuickRatingsAndTodayEditPreserveEntry() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    app.buttons["How do you feel?"].tap()
    let rating = app.buttons["journal-energy-4"]
    XCTAssertTrue(rating.waitForExistence(timeout: 3))
    guard rating.exists else { return }
    rating.tap()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Journal check-in saved"].waitForExistence(timeout: 5))
    app.buttons["today-journal-check-in"].tap()
    XCTAssertTrue(app.buttons["journal-energy-4"].isSelected)
    app.buttons["Cancel"].tap()
  }
  @MainActor func testWorkoutNotesAreImmediatelyReachableWithoutHeartRate() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    app.tabBars.buttons["Activity"].tap()
    app.buttons["Start Padel"].tap()
    app.buttons["Finish"].tap()
    app.buttons["confirm-finish-workout"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.textFields["workout-notes-field"].isHittable
        || app.textViews["workout-notes-field"].isHittable)
  }
}

extension TempoUITests {
  @MainActor func testDeviceDetailsProvideHistoryStatusAccess() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--demo"]
    app.launch()
    let settings = app.buttons["Bands, sync and settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    wait(
      for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: settings)],
      timeout: 30)
    settings.tap()
    app.buttons["Manage and reconnect bands"].tap()
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'registered-band-'")).firstMatch
      .tap()
    for _ in 0..<3 where !app.buttons["device-history-status"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["device-history-status"].isHittable)
    app.buttons["device-history-status"].tap()
    XCTAssertTrue(app.navigationBars["Band status"].waitForExistence(timeout: 5))
  }
}
