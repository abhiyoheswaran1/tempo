# Latest verification — 13 October 2026

Software verification and physical collection evidence are separate.

- Core: 134 tests passed in Debug and 134 in Release, including sleep coverage/missing-data states and history sequence reconnect boundaries.
- Simulator: the final two focused tests passed for visible battery percentage/separate Settings and possible-sleep review/confirmation. Earlier affected-screen runs passed four Settings/product/accessibility capture tests and four battery/live/trends/activity tests. These are focused runs, not a new full-suite claim.
- Signed iPhone Release build succeeded with the owner’s local signing configuration. Public project signing configuration was not changed.
- Sixteen unmodified real simulator screenshots use isolated synthetic or empty datasets; checksums and test provenance are in screenshots/capture-manifest.json. Synthetic records never enter the normal cloud dataset.

## Physical evidence and remaining acceptance

An owned Whoop 5 on firmware 50.42.1.0 successfully completed historical transfer after normal iOS pairing. The private database contained 2,632 durably stored historical HR readings, 3,067 retained frames and a checkpoint; SQLite integrity checked successfully. Returned older timestamps preceded the diagnostic launch. This proves recent catch-up on that instance, not unlimited retention or successful overnight sleep detection. Earlier overnight records were not returned. No personal payloads or screenshots are published.

Tonight’s test remains open: keep Tempo as the band’s collector, reopen it tomorrow, verify actual overnight coverage and review any possible-sleep suggestion. HR-only possible sleep is experimental and requires confirmation; it does not reproduce Whoop’s staging or proprietary algorithms. Ambiguous quality flags remain excluded from physiological analytics.

A prior physical CPU resource termination remains D05 in Improvements.md. Coalescing analysis after transfer chunks settle and using an optimised Release build do not establish that this problem is resolved.

Reproduce software checks with `swift test` and `swift test -c release`, then build Tempo.xcworkspace / Tempo for an iPhone. Simulator captures do not prove Bluetooth, background execution or CloudKit restore.

## Follow-up collection check

A later on-device diagnostic run completed with 7,284 historical HR readings committed in that attempt. The inspected database contained 11,710 historical HR observations spanning UTC 09:40:13–13:28:55 on 13 October. Two gaps longer than two minutes remain within the returned history; retained R18 frames did not contain timestamps inside those intervals. Overnight records were absent. This distinguishes missing band-returned records from cloud success or a purely live chart. No claim that all gaps are repaired.

The redundant Today header battery line was removed; the percentage remains beside the source band. Its focused UI test and signed Release build passed.

## Live dashboard refinement

Both focused UI tests passed: standard live/band interactions and maximum-text/dark evidence reachability. The new coverage/collapsed-detail assertions first failed before implementation. The final signed Release build succeeded and was installed on the connected test iPhone. The refreshed gallery image is a genuine isolated synthetic simulator capture. This visual refinement does not establish recovery of missing band records or resolve CPU reliability D05.

## Dashboard refresh isolation

Two focused simulator tests passed: live/band interactions and maximum-text/dark evidence reachability. Signed Release build succeeded and installed. Whole-dashboard one-second timing was replaced by independent live-reading/workout components; the history chart keeps its own refresh cadence and same-context snapshot during reload. Physical smoothness and CPU profiling remain open; no FPS improvement is asserted.
