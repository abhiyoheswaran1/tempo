# Latest verification — 2026-10-13

| Check | Evidence / boundary |
|---|---|
| Swift core |122 tests passed,0 failures;13 WHOOP5 history tests cover firmware/range/padding, R18 parsing, generation, idempotent archives, transaction rollback, quality exclusion, descriptive coverage, source priority, deadlines and late commits across retries |
| Simulator |All19 UI tests passed; four affected-screen checks passed, followed by final capture/contrast reruns. Native app/extension compiled on installed iOS27 runtime, minimum target iOS26 |
| iPhone compilation |Unsigned generic iPhoneOS build passes; this is not signing, installation or hardware validation |
| Journal/workouts |Quick nullable ratings, same-day edit identity, notes/exertion first, missing-data summaries and native disclosures; read-only task reviews and UI regressions passed |
| History software |Read-confirmed W4 41.17.6.0; W5 50.42.1.0 plus positive range. Durable raw/sample/checkpoint commit before normal ACK, independent generation layout and per-attempt callback scope |
| Quality |Opaque R18 fields retained; excludes these records from physiological analytics, suggestions and Health export. Descriptive chart includes explicit experimental context; readiness1.2/night-cache3 |
| Review |Final whole-branch review plus scoped attempt/deadline review found no concrete important blocker |
| Gallery |14 unmodified successful-test simulator PNGs, synthetic or empty isolated datasets; checksum/dimension/timestamp provenance manifest. No owner health screenshot published |

Reproducible local evidence: `/private/tmp/tempo-history-attempt-verified-core.log`, `/private/tmp/tempo-overnight-ui.xcresult` (full19), `/private/tmp/tempo-overnight-release-ui.xcresult` (four affected), `/private/tmp/tempo-journal-contrast-capture.xcresult`, `/private/tmp/tempo-shipping-captures.xcresult`, `/private/tmp/tempo-overnight-final-shipping-phone.log`. Intended failures were observed before fixes in decoder/range/quality/selection/chart/detection/deadline/attempt and navigation/journal/workout regressions. Test fixtures are original constructed packets, not captured proof of a band transfer.

Physical bands tested by the implementation agent:0. Signed CloudKit/HealthKit integration sessions:0. The owner separately reports live Whoop5 HR, firmware50.42.1.0 and an updating widget timestamp. Those observations do not establish memory offload, overnight quality, background continuity, two-phone restore or full widget/Live Activity behavior. Actual W4/W5 history recovery remains C05/C02; signed lifecycle, source switching, cloud, Health and accessibility gates stay open in [Improvements](Improvements.md). QuartzCore/PointerUI/App Group messages remain documented without a physical-fix claim.

This is a buildable engineering implementation for physical testing, not a validated daily-use acceptance sign-off. Follow [the catch-up checklist](HardwareValidation.md#whoop5-504210-catch-up-acceptance).
