# Latest verification — 13 October 2026

Software verification is separate from physical collection acceptance.

## Trends refinement

- 150 core tests passed, including new period-summary cases for missing days, empty ranges and truncation. The new summary API was absent in the initial test build before implementation.
- Both final-source simulator flows passed: standard Trends metric/day evidence and maximum Dynamic Type/dark Trends-to-Live navigation. An earlier large-text run failed because explanatory headings pushed the metric selector below the fold; the layout was simplified and the unchanged large-text check then passed.
- Fresh unmodified Trends and sleep-Trends captures were inspected and added to the gallery with updated manifest checksums. Read-only review found and corrected a sleep refresh identity omission; final review found no remaining important changed-line defects.
- Signed Release build succeeded and installed on the test iPhone. This verifies installation, not physical smoothness or missing history recovery.

## Integrity audit

- 147 core tests passed in Debug and 147 in Release, including 13 new regression/boundary cases. Reproducers first failed for query filtering/deletion limits, retry state/races, timestamp safety and workout chronology.
- Broad simulator sweep: 20 of 21 tests passed. The placement test failed because it tapped a lazy List row below the fold; its navigation was corrected to scroll to the control. The final-source rerun passed all four selected placement, workout, empty-state and possible-sleep flows; a subsequent final-source Live dashboard test also passed.
- Signed iPhone Release build succeeded and installed using the owner’s local signing configuration. Owner project/scheme changes were preserved and excluded from public commits. Launch was blocked because the phone was locked; open Tempo after unlocking.
- Independent read-only review identified a stale-failure retry race; it was reproduced, fixed and rereviewed with no remaining critical/important changed-line findings.
- Details and open outcomes are in [BugAudit.md](BugAudit.md). This does not certify all product acceptance criteria.

## UI and capture evidence

Sixteen unmodified simulator screenshots use isolated synthetic or empty datasets; checksums/test provenance are in screenshots/capture-manifest.json. The separate Settings gear, source-band percentage, missing-data states, sleep review and Live dashboard have simulator coverage. Live BPM/workout timers are isolated from the dashboard list/history; physical smoothness and CPU profiling remain D05. Synthetic records never enter the normal cloud dataset.

## Physical collection evidence and remaining gates

On the owned Whoop 5 firmware 50.42.1.0, normal iOS pairing enabled Hello, notifications, range and historical transfer. An earlier private database inspection confirmed 2,632 historical HR observations, 3,067 retained frames and a checkpoint with SQLite integrity OK. A later transfer committed 7,284 readings in that attempt. Its inspected database contained 11,710 historical HR observations spanning UTC 09:40:13–13:28:55 on 13 October.

Two gaps longer than two minutes remained inside the returned history, with no retained R18 timestamps inside those intervals. Overnight records were absent. This proves recent catch-up on that instance, not unlimited retention, overnight recovery or complete gap repair. Personal payloads/screenshots stay private.

Tonight’s test remains open: use Tempo as the collector, reopen it tomorrow and verify actual overnight coverage and any possible-sleep suggestion. HR-only possible sleep is experimental and requires confirmation; it does not reproduce Whoop staging or proprietary algorithms. Unresolved quality flags remain excluded from physiological analytics.

Physical background recovery, CPU resource termination, signed two-phone CloudKit restore, Health permissions and accessibility audit remain open. The audit also recorded A05: imported Health sleep stage intervals still need continuous-night reconciliation. No claim that these issues are resolved.

## Reproduction

Run `swift test` and `swift test -c release`. Open Tempo.xcworkspace, select Tempo, build for an iPhone or simulator, and run TempoUITests. Simulator tests do not prove Bluetooth, continuous background execution or CloudKit restore.
