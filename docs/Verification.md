# Latest verification — 13 October 2026

Software verification is separate from physical collection acceptance.

## Today card sizing and movement details

-150 core tests passed. Card equality first failed for both top alignment and height, then passed after intrinsic-height/layout correction, including a saved manual sleep revision matching the reported case.
- The dedicated movement route regression first failed against ActivityView, then passed with daily load/coverage/intensity details. Three selected card/movement/large-text-dark Today flows passed; the final card/manual-save and movement rerun passed both tests. Two further empty-data/battery flows passed. This was targeted verification, not a full UI suite.
- Populated card frame equality is asserted; the empty-data layout was visually inspected with matching card bounds. Accessibility text retains stacked cards; the existing maximum-text-dark Today navigation check passed. The new movement detail does not yet have a dedicated maximum-text test.
- Signed Release build succeeded and installed. Fresh synthetic Today/manual-sleep, movement, battery and empty captures were inspected and their manifests updated. Read-only review found no important blockers. No load or sleep algorithm changed.

## Sleep detail refinement

- All150 core tests passed. All three final-source simulator checks passed and cover sleep detail, saved-origin revision refresh, adding another session, and maximum-text dark-mode access to correction controls. The initial new detail test failed before the new headline/latest-revision projection existed. A large-text test initially targeted the child label instead of its accessible button; the corrected button interaction passed.
- Review identified sparse-HR omission and inconsistent chart timezone labels; both were corrected. The chart shows isolated readings without inventing continuous coverage and formats times in the recorded timezone. A real changed-time DatePicker interaction remains outside this UI test's coverage; it checks save/projection refresh rather than a duration change.
- Signed Release build succeeded and installed on the test iPhone.
- The new sleep-detail image is an unmodified, clearly labelled synthetic simulator capture. No detection or recovery algorithm changed.

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

Eighteen unmodified simulator screenshots use isolated synthetic or empty datasets; checksums/test provenance are in screenshots/capture-manifest.json. The separate Settings gear, source-band percentage, missing-data states, sleep review and Live dashboard have simulator coverage. Live BPM/workout timers are isolated from the dashboard list/history; physical smoothness and CPU profiling remain D05. Synthetic records never enter the normal cloud dataset.

## Physical collection evidence and remaining gates

On the owned Whoop 5 firmware 50.42.1.0, normal iOS pairing enabled Hello, notifications, range and historical transfer. An earlier private database inspection confirmed 2,632 historical HR observations, 3,067 retained frames and a checkpoint with SQLite integrity OK. A later transfer committed 7,284 readings in that attempt. Its inspected database contained 11,710 historical HR observations spanning UTC 09:40:13–13:28:55 on 13 October.

At that earlier inspection, two gaps longer than two minutes remained inside the returned history, with no retained R18 timestamps inside those intervals; overnight records were absent. The owner subsequently reported historical retrieval fixed. These earlier observations are a dated validation boundary, not a claim that the current app still has the same missing history. This proves recent catch-up on that instance, not unlimited retention, overnight recovery or complete gap repair. Personal payloads/screenshots stay private.

Tonight’s test remains open: use Tempo as the collector, reopen it tomorrow and verify actual overnight coverage and any possible-sleep suggestion. HR-only possible sleep is experimental and requires confirmation; it does not reproduce Whoop staging or proprietary algorithms. Unresolved quality flags remain excluded from physiological analytics.

Physical background recovery, CPU resource termination, signed two-phone CloudKit restore, Health permissions and accessibility audit remain open. The audit also recorded A05: imported Health sleep stage intervals still need continuous-night reconciliation. No claim that these issues are resolved.

## Reproduction

Run `swift test` and `swift test -c release`. Open Tempo.xcworkspace, select Tempo, build for an iPhone or simulator, and run TempoUITests. Simulator tests do not prove Bluetooth, continuous background execution or CloudKit restore.
