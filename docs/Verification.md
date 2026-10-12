# Verification ledger

Environment inspected2026-10-12: Apple Silicon Mac; Xcode27.0 build27A266a; iPhoneOS/iPhoneSimulator27.0 SDK; iOS27.0 simulator runtime. Project deployment target26.0. No physical bands or signed developer provisioning were used.

Software checks are recorded separately from hardware acceptance:
- Core suite: see final test count/results below; actual SQLite, constructed packets and deterministic domain tests.
- Native simulator build including WidgetKit/ActivityKit extension: successful.
- Unsigned generic iPhone/device build: successful before final regression fixes; final verification listed below.
- Simulator UI:2 tests successful for empty tabs/workout transitions and labelled isolated demo; final rerun listed below.

Initial build issues resolved: command-line tools/Xcode mismatch; restricted compiler cache; PackageDescription iOS26 constant availability; Foundation Measurement naming collision; SwiftUI closure brace; simulator architecture mismatch (explicit ARCHS=arm64 for interaction tests); Health string/Data tombstone conversion.

Independent code review caught and drove regressions for stable Health revision reconstruction, deleted-measurement projection, source transition closure, mode-switch serialization, local revision compare-and-append and exported Health sample provenance. No review or parser result proves hardware validity.

Local artifacts are in /tmp/tempo-core-tests.log, /tmp/tempo-ui-tests.log and /tmp/tempo-device-build.log during this session; reproduce with commands in Setup.md. These temporary logs are not source payloads and contain no real health data.

## Final results (2026-10-12)

- Core:33 XCTest tests passed,0 failures.
- Clean arm64 iPhone simulator build + interaction suite:2 tests passed,0 failures. Native app, WidgetKit/ActivityKit extension and UI runner compiled.
- Final unsigned generic iPhoneOS build:BUILD SUCCEEDED. This does not provision, install, or validate a physical phone.
- `git diff --check`: no whitespace errors. Work is left in the supplied workspace; no push, merge or signing identity changes performed.
- The fixed namespace ID in portable preferences is computed. Xcode may emit an informational AppIntents metadata warning because no AppIntents dependency is present; the app uses no such intents.

Hardware validation:0 bands tested. CloudKit/HealthKit physical integration:0 signed-phone validation sessions. No daily-use readiness claim.

Visual review found and corrected demo banner/navigation overlap. The final UI regression includes a geometry assertion. Workout detail now reads its historical range, and a core test verifies bounded chart projection with separated gap segments.

## Branding and screenshot update (2026-10-12)

Original rounded-T vector branding exported as SVG, RGB 1024px icon, transparent PNG and Xcode-ready asset folders. Icon dimensions/no-alpha and byte-identical app/export assets validated. Today and Settings display the mark; the widget uses the same template geometry. The branding UI assertion was observed failing before integration and passes afterward.

The updated simulator suite passes all3 tests, including real six-screen capture via XCTest attachments. Screenshots were visually inspected and copied without postprocessing; their source-test/timestamp/dimensions/checksums are in docs/screenshots/capture-manifest.json. Synthetic/demo data only, no physical-band validation. Fresh unsigned iPhone build:BUILD SUCCEEDED. Core logic unchanged; prior33 core tests remain the recorded core verification.

## Automatic activity update (2026-10-12)

- Core:43 XCTest tests passed,0 failures, including ten activity tests for sustained HR, coverage/gaps, existing workouts, source switches, duplicate records, replay and synthetic revision/archive isolation.
- Simulator:4 UI tests passed,0 failures; confirmation creates one estimated workout and repeated scans do not recreate it. Seven actual simulator screenshots exported unchanged with capture manifest.
- Unsigned iPhoneOS app and widget build:BUILD SUCCEEDED. Simulator tests also compile the app and extensions.
- Read-only code review identified synthetic revision/archive leakage, stale overlapping suggestions and confirmed-estimate Health export eligibility; fixes reviewed with no remaining critical findings.
- The first activity UI run exposed repeated readiness timeline computation. Reusing the per-calculation projection and per-render readiness result resolved the delay; rerun passes. A subsequent test needed to scroll to the confirmation control in the native Form; corrected test navigation passes.

Physical-band detection accuracy, background input coverage, signed Health export and two-phone sync remain unverified. This update does not complete the outstanding original acceptance criteria.

## Wearing placement update (2026-10-12)

- Core:49 XCTest tests passed,0 failures, including six placement tests for effective-time boundaries, per-band separation, contradictory reports, replay/immutable measurements, readiness confidence and conflicting moved-timestamp projections.
- Simulator:5 UI tests passed,0 failures, including reporting wrist, upper arm and underwear without losing earlier reports. Seven existing screenshots refreshed from actual simulator attachments; checksums/capture timestamps updated.
- Unsigned generic iPhone app and extension build:BUILD SUCCEEDED. `git diff --check` passes.
- Review identified two conflict projection cases: an older known location resurfacing and an intervening report masking disputed moved timestamps. Regression tests failed before fixes and pass afterward. Final read-only review reports no remaining important defect.

All positions are manual context. No physical-band placement/accuracy testing was performed; no firmware location commands or new motion models are implemented. Readiness v1.1 uses a documented conservative confidence heuristic, not calibrated accuracy. Full28-day placement calibration remains future work.
