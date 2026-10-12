# Tempo screenshots

These PNGs are actual screen captures from the running Tempo iOS app on the iPhone 18 Pro simulator, using the iOS 27 runtime. They are not mockups, device photographs or proof of band/CloudKit operation. All health values shown are explicitly synthetic demo data. The workout capture shows unavailable live HR honestly.

Captured through `TempoUITests.testCaptureProductScreenshots` with `--ui-testing --demo`. The test waits for the isolated demo dataset to finish loading, navigates the native screens and attaches each screenshot to its Xcode result bundle. Files are copied directly from those attachments without cropping, overlays or other postprocessing. `capture-manifest.json` records the source test, capture timestamps, dimensions and SHA-256 checksums.

Screens: Today, activity selection, active workout, trends, readiness explanation, settings.

To reproduce, run the Tempo scheme's UI tests with an installed iPhone simulator. Export attachments from the resulting `.xcresult` bundle:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun xcresulttool export attachments --path /path/to/results.xcresult --output-path /tmp/tempo-attachments
```

Screen captures demonstrate software layout and navigation only. They must not be represented as physical-hardware validation.
