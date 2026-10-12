# Latest verification — 2026-10-12

Completed software IDs live in Completed.md; unresolved physical gates remain in Improvements.md and KnownLimitations.md.

| Check | Result |
|---|---|
| Swift core suite | 100 tests passed, 0 failures; bounded live history, powered-command policy, latest-reading index, malformed battery bytes, freshness and sleep expiry included |
| iPhone simulator suite | Redesigned product passed all15 tests; five affected Today/capture tests passed after review fixes; final capture/baseline and maximum-text layout reruns |
| Native executable | Tempo workspace/scheme builds app and widget extension; minimum iOS26 |
| Unsigned generic iPhoneOS build | BUILD SUCCEEDED |
| Captures | Thirteen unmodified successful-test simulator attachments, synthetic or empty isolated datasets; timestamp/dimensions/SHA-256 manifest |
| Today | Native large title, compact readiness, live-reading hero, paired sleep/movement summaries, vertical accessibility layout, journal and manual/pull refresh |
| Smoothness | Latest valid per-device reading index avoids full-history live-render scans; presented readiness/load summaries refresh after load/foreground/coalesced collection; current eligible sleep invalidates cached readiness |
| Battery | Optional single-instance standard BLE report, validated bytes,15-minute read limit and one-hour header expiry; VoiceOver value and timestamp/accuracy disclosure; actual band support unverified |
| Trends/Live | One selected metric and same-day provenance; four-hour bounded chart with short ranges, exact input statistics and gap preservation; stale/source states remain explicit |
| Bluetooth | Commands require powered-on central; restored peripherals deferred; battery notification callbacks cannot claim HR started or failed |
| Read-only review | Sleep cache expiry, missing VoiceOver values and battery/HR status confusion identified and corrected |

Local evidence: `/private/tmp/tempo-today-verified-core.log`, `/private/tmp/tempo-today-redesign-ui.xcresult` (full15), `/private/tmp/tempo-today-verified-ui.xcresult` (affected rerun), `/private/tmp/tempo-today-final-layout-device.log`. Capture provenance: [manifest](screenshots/capture-manifest.json).

Physical bands tested by the implementation agent:0. Signed CloudKit/HealthKit integration sessions:0. Physical battery accuracy, wear accuracy, background collection, two-phone restore, signed widgets/Live Activities, iOS26 runtime and VoiceOver remain unverified. The owner separately confirms that the signed phone widget timestamp updates; the CFPrefs warning and remaining delivery fields/relaunch audit remain open. QuartzCore/PointerUI diagnostics remain documented without a hardware fix claim. WHOOP4 transfer is experimental and physically unverified; WHOOP5 catch-up remains unavailable. Compilation and synthetic simulator tests do not establish daily-use readiness.

History extension:100 core tests pass, including transfer boundaries/commit-before-ACK, raw archive replay/rollback, special/empty chunk refusal, successive chunks, discarded/partial cross-channel bytes, legacy backup import, schema1 migration preserving pending uploads and backfill never labelled live. Three affected simulator tests passed, followed by two final band-status/capture tests after refining unavailable-state copy; the pull gesture was corrected to start below the expanded native navigation title. Unsigned iPhone build passes. Evidence: `/private/tmp/tempo-history-release-final-core.log`, `/private/tmp/tempo-history-verified-ui.xcresult`, `/private/tmp/tempo-history-final-phone-build.log`. None is a physical backfill result. The owner's screenshot separately shows current Whoop5 live HR plus a past gap, not demonstrated history recovery.
