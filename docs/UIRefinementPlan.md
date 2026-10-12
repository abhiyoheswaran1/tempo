# Tempo UI refinement implementation plan

> Execute inline using executing-plans; one final read-only review. Keep only unfinished steps here after completion, and use Completed.md for compact closure.

Goal: calmer useful native screens, with accurate evidence and a small maintained backlog.
Architecture: pure presentation/date/aggregation rules in TempoCore; thin SwiftUI summaries and shared status/workout controls. Immutable observations, revision ancestry and analytical formulas retained.
Tech: Swift6, SwiftUI/Charts, SQLite actor; iOS26 minimum, no third-party dependency or fabricated API.
Spec: the eight approved review findings, tracked UX01–UX08 in Improvements.md.

- [ ] Today/evidence: fail core tests for headline/evidence bands and last overnight versus naps/older dates; implement presentation rules, compact hierarchy, measured coverage, date-aware sleep and useful actions. No readiness percentage interpreted as calibrated accuracy.
- [ ] Status/workouts: verify native accessory API in installed SDK; add compact source freshness/placement control and quick sheet; frequent activity ordering, cross-tab active session controls and finish-summary sheet. Test interaction, empty/stale states, and persisted pauses/source continuity.
- [ ] Trends: fail aggregation tests for irregular sampling, duplicate bands, gaps, DST and provenance. Implement weighted covered HR, per-metric summary semantics, missing-day line segments, units and accessible point details. Keep derived/imported values distinguishable; do not invent overnight inputs.
- [ ] Accessibility/verification: large-text adaptive rows and summaries, light/dark captures, accessible chart descriptions; UI regression suite, core tests, unsigned iPhone build, visual QA and final review. Keep physical audit ticket V05 open.
- [ ] Update records: close only passing UX items; compact completion/evidence log, update README/docs/capture manifest, commit and push authorized changes, leave workspace buildable.

Review focus: stale data never called current; no nap/old sleep called last night; unknown placement does not establish wear; irregular HR never becomes arbitrary daily latest value; demo never reaches normal sync/Health; paused workout controls and note edits persist.
