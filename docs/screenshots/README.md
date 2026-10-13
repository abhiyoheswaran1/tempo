# Tempo screenshots

These PNGs are actual screen captures from the running Tempo iOS app on the iPhone 18 Pro simulator, using the iOS 27 runtime. They are not mockups, device photographs or proof of band/CloudKit operation. All health values shown are explicitly synthetic demo data. The workout capture shows unavailable live HR honestly.

Captured through `TempoUITests.testCaptureProductScreenshots` with `--ui-testing --demo`. The test waits for the isolated demo dataset to finish loading, navigates the native screens and attaches each screenshot to its Xcode result bundle. Files are copied directly from those attachments without cropping, overlays or other postprocessing. `capture-manifest.json` records the source test, capture timestamps, dimensions and SHA-256 checksums.

Today now includes the live/collection panel before the daily summaries and a circular manual Refresh control; pull-to-refresh invokes the same action.

Screens: Today, activity selection, active workout, completed workout summary, trends, readiness explanation, settings, experimental activity review, and maximum Dynamic Type in dark mode. The activity review comes from `testDetectedActivityRequiresConfirmationAndDoesNotRepeat` with `--activity-detection-demo`. The dark/maximum-text capture comes from `testLargeTextDarkModeKeepsPrimaryActionsAccessible` with `--large-text --dark`. The live dashboard comes from `testLiveDashboardAndBandManagementKeepDemoHonest` with `--live-dashboard-demo`; it never fakes a Bluetooth connection. All demo captures use isolated synthetic data.

To reproduce, run the Tempo scheme's UI tests with an installed iPhone simulator. Export attachments from the resulting `.xcresult` bundle:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun xcresulttool export attachments --path /path/to/results.xcresult --output-path /tmp/tempo-attachments
```

Screen captures demonstrate software layout and navigation only. They must not be represented as physical-hardware validation.

The current Trends and sleep-Trends images were refreshed by `testTrendsSelectsOneMetricAndAccessibleDayEvidence`, from its successful final-source simulator run. The Trends overview shows recorded-day coverage and a descriptive median; these remain synthetic examples, not physical sensor validation.

Sleep detail was captured by `testSleepDetailLeadsWithTimingAndUpdatesCorrection` from the successful final-source run. It uses isolated synthetic data and deliberately displays only partial HR coverage. The original PNG was inspected and copied without postprocessing.

Today equal-card capture comes from `testTodaySummaryCardsHaveEqualHeight`, including a manual sleep revision inside the isolated demo dataset. Daily movement evidence comes from `testTodayMovementOpensDailyEvidenceInsteadOfWorkouts`. Empty Today and demo battery captures were also refreshed by their successful tests. These images retain original simulator pixels and disclose synthetic/empty data.

Day explorer, sleep rhythm, daily observation evidence and the updated Today capture come from the successful final feature tests on the isolated Tempo audit simulator. The gallery has21 captures; original attachment pixels and provenance are retained in the manifest.

Sleep rhythm discoverability captures refresh Trends and Sleep detail from `testSleepRhythmIsFeaturedInTrendsAndLinkedFromSleep` and the standard Trends evidence flow. The Live source/sync capture comes from the successful Live dashboard regression and shows no idle workout row. All23 captures remain unmodified synthetic/empty simulator evidence; hardware validation is separate.

Today and Recorded coverage were captured by `testTodayRecordedCoverageExplainsGapsAndReliabilityIsOptIn`; the system reporting screen contains no fabricated reports.
