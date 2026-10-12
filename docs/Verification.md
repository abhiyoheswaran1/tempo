# Latest verification — 2026-10-12

Current evidence only. Completed IDs live in Completed.md; older investigations remain in Git. Physical gates remain in Improvements.md and KnownLimitations.md.

| Check | Result |
|---|---|
| Swift core suite | 72 tests passed,0 failures |
| iPhone simulator suite | 9 tests passed,0 failures; final contact-status change additionally passes focused dashboard/removal rerun |
| Native executable | Tempo workspace/scheme builds Tempo.app/Tempo, app/widget/UI runner; minimum iOS26 |
| Unsigned generic iPhoneOS build | BUILD SUCCEEDED after final contact-status change |
| Captures | ten actual, unmodified successful-test XCTest attachments; source/timestamp/dimensions/SHA-256 manifest |
| Band policy | pending/connected connection idempotence, explicit pause across ledger restoration, interrupted link intent, late callbacks, generation evidence, history-preserving registry deletion/restoration |
| Wearing/selection | both usable worn sources retain current automatic selection; fresh connected measured contact reports required; off-body physiology excluded while contact remains visible |
| Workout integrity | manual disconnect closes source, same-band reconnect starts another segment, finishing never extends an already-closed source gap |
| Sync | five-minute freshness/pending-change policy,60-second automatic cooldown, failed-pass backoff, dataset identity guards after awaits; actual CloudKit behavior needs signed validation |
| UI | live dashboard/demo honesty, removal confirmation, Today/tabs, cross-tab workout controls, stale sleep, placement changes, maximum text/dark mode |
| Review | remapping/sync dataset races and finish-gap findings fixed; final contact evidence review has no important unresolved finding |

Red/green checks covered absent connection/freshness APIs, disconnected source gaps and off-body contact evidence. Simulator runs caught offscreen controls and duplicate accessibility representations of a native confirmation button; removal is moved ahead of the capability list and the test targets the explicit confirmation action.

Reproduce with README/Setup commands. Local session artifacts: `/private/tmp/tempo-band-final-core.log`, `/private/tmp/tempo-band-delivery-ui.log`, `/private/tmp/tempo-band-delivery-ui.xcresult`, `/private/tmp/tempo-band-contact-ui.log`, `/private/tmp/tempo-band-contact-ui.xcresult`, `/private/tmp/tempo-band-device.log`. Captures come from the full simulator run and final focused live-dashboard run. See the manifest for each source test.

Physical bands tested:0. Signed CloudKit/HealthKit phone sessions:0. iOS26 runtime, VoiceOver, actual background reliability, wear/contact accuracy at all placements and cross-phone restore remain unverified. A passing unsigned build neither provisions an iPhone nor establishes daily-use readiness. Complete proprietary historical retrieval is still unavailable.
