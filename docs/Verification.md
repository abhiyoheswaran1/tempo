# Latest verification — 2026-10-12

This file is the current evidence summary. Completed IDs live in Completed.md; detailed older investigation is retained in Git (`git log -- docs/Verification.md`). Hardware gates remain in Improvements.md and KnownLimitations.md.

| Check | Result |
|---|---|
| Swift core suite | 60 tests passed,0 failures |
| iPhone simulator suite | 8 tests passed,0 failures |
| App workspace, Tempo scheme | simulator app/widget/UI-runner build and tests succeed |
| Unsigned generic iPhoneOS build | BUILD SUCCEEDED; app and widget compile |
| Executable configuration | native application product, Tempo.app/Tempo, iPhoneOS + Simulator, minimum iOS26 |
| Screenshots | nine actual XCTest attachments, unchanged; manifest includes source test/timestamp/dimensions/SHA-256 |
| Accessibility simulation | maximum Dynamic Type `.accessibility5`, dark mode; primary actions reachable |
| Source/workout flows | band HR-only filtering, cross-tab pause/resume, active/finished modal titles, completion summary, optional exertion |
| Date/data integrity | older/future/nap inputs cannot supply current readiness; DST local-day summaries, gap/overlap/deletion handling, midnight evidence retained |
| Read-only review | old-readiness and historical-refresh findings corrected; no remaining important finding in reviewed fixes |

Core red/green evidence covered arbitrary-last-HR weighting, midnight provenance and old-sleep eligibility. The initial UI gate failed before the new compact status/accessory flow. Interaction failures caught child navigation titles and offscreen large-text navigation; fixes pass. Visual review replaced absent zone data with an unavailable state and shortened elapsed-time formatting.

Reproduce with README/Setup commands, using Tempo.xcworkspace or Tempo.xcodeproj and scheme Tempo. Latest local artifacts during this session: `/private/tmp/tempo-ui-final2-core.log`, `/private/tmp/tempo-ui-delivery.log`, `/private/tmp/tempo-ui-delivery-device.log`, `/private/tmp/tempo-ui-delivery-tests.xcresult`.

Physical bands tested:0. Signed HealthKit/CloudKit phone-validation sessions:0. iOS26 runtime, VoiceOver, real background reliability and cross-phone restore remain unverified. A passing unsigned build does not provision/install a phone or establish daily-use readiness.
