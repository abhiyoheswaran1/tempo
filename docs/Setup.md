# Open the runnable iPhone app

Open `Tempo.xcworkspace` or `Tempo.xcodeproj`; select **Tempo**, not **TempoCore**, as the scheme. The repository root/Package.swift opens the non-executable core library. `Scripts/Open-Tempo.command` opens the app workspace explicitly. Choose an iPhone/iPhone simulator running iOS26+, then configure signing for Tempo and TempoWidgets. Native Run → Info → Executable is `Tempo.app`. The app binary is created during build and is not a checked-in source file.

# Build and install Tempo

## Tools

Xcode26 or newer with an iOS26 SDK, iPhone on iOS26+, and Swift6. This workspace was inspected with Xcode27.0 (27A266a); code targets iOS26 and uses established APIs, not iOS27-specific features. The installed simulator runtime is iOS27; iOS26 runtime verification remains required.

Open `Tempo.xcodeproj`. It contains Tempo and TempoWidgets (WidgetKit summary + workout Live Activity), plus TempoUITests. TempoCore is a local Swift package. No network dependency download is needed. Regenerate project configuration after adding files with `python3 Scripts/generate_project.py`; identifiers remain in Configuration.xcconfig.

## Signing

1. Add your Apple developer account in Xcode Settings → Accounts.
2. Register unique identifiers for app and `.widgets` extension. Replace `TEMPO_BUNDLE_ID`, `TEMPO_APP_GROUP`, `TEMPO_CLOUD_CONTAINER` in Configuration.xcconfig. Set `DEVELOPMENT_TEAM` to your team ID.
3. Enable iCloud → CloudKit, HealthKit and App Groups for Tempo. Enable the same App Group for TempoWidgets. Keep automatic signing enabled for both targets.
4. Ensure the CloudKit container and App Group exist in your developer account and profiles. Private CloudKit/HealthKit capabilities may require a paid developer membership; a free personal team is not equivalent to the required entitlements.
5. Choose your physical iPhone, enable Developer Mode, trust the developer profile if asked, then Run. No App Store submission or hosted account is needed.

Bluetooth permission is requested when discovery/connection starts. Health permissions are requested only in Apple Health settings after selecting types. This build does not request location. Do not add credentials to the repository.

## Command-line checks

If xcode-select points at command-line tools, use this developer directory without changing global system settings:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Tempo.xcodeproj -scheme Tempo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tempo-xcode CODE_SIGNING_ALLOWED=NO build
swift test --scratch-path /tmp/tempo-core-tests
xcodebuild -project Tempo.xcodeproj -scheme Tempo -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/tempo-device CODE_SIGNING_ALLOWED=NO build
```

Use Xcode's Swift toolchain if the shell's `swift` points to mismatched command-line tools. Select an installed iPhone simulator destination for `xcodebuild test`. An unsigned device build verifies compilation, not installation or capabilities.

## First real collection

Keep demo off. Settings → Manage bands → choose generation → Scan. Put the owned band into its supported pairing / heart-rate broadcast mode. Explicitly identify the band, especially for generic HRS advertisements. Register both; they remain distinct portable device identities. The current transport connects to one at a time. On a restored phone choose “Reconnect [existing band]” before selecting the peripheral; do not create a new identity merely because the name is similar.

Start a manual workout and verify measured HR, timestamps and persisted coverage. End it, relaunch, inspect history, export a backup and compare counts. Do this separately with each generation before relying on collection. Battery/haptic/alarm/motion controls are unavailable pending physical protocol validation; no successful hardware behavior is simulated.

## Demo

Settings → Simulator demo, or launch argument `--demo`. A prominent synthetic banner appears. Demo uses an isolated in-memory database, cannot upload/export to Health, and cannot be exported into normal backup history. Turn it off to reopen the real local dataset. UI tests use `--ui-testing` and an isolated in-memory database. Simulator BLE behavior is not hardware evidence.
