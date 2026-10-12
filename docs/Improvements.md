# Tempo active improvements

Single working backlog. Update when scope changes or evidence closes an item. Priorities: P0 integrity/collection, P1 continuity/usefulness, P2 polish/extensions. Status: open, in progress, or awaiting hardware. Remove a ticket only after its acceptance checks pass; append one compact line to [Completed](Completed.md). Durable contracts belong in the linked technical docs, not duplicated ticket prose. Git retains superseded plans and detailed investigation history. Never delete unresolved findings or treat compilation as physical validation.

## Current refinement

| ID | Priority/status | Finding → acceptance |
|---|---|---|
| UX01 | P1 in progress | Today headline dominates; readiness/sleep/movement should be concise and visible at standard text size. |
| UX02 | P1 in progress | Heuristic confidence looks calibrated; replace percentages with evidence categories, keep methodology/coverage accessible. |
| UX03 | P2 in progress | Repeated equal cards dilute hierarchy; emphasize readiness, quieter supporting rows, native navigation glass. |
| UX04 | P1 in progress | Band status/placement buried; compact fresh/stale status opens actionable collection and placement controls; no unsupported battery placeholder on Today. |
| UX05 | P1 in progress | Workout controls/history fragmented; frequent activities first, recording accessible across tabs, finish opens honest summary and notes/exertion. |
| UX06 | P1 in progress | Latest daily HR is arbitrary; justified per-metric aggregates, units, quality/provenance, missing-day gaps and personal context. |
| UX07 | P1 in progress | Technical missing states/old sleep mislabelled; actionable empty states and date-aware overnight/nap selection. |
| UX08 | P2 in progress | Accessibility verification thin; scaled layouts, chart descriptions, largest-text and dark-mode simulator checks. Physical VoiceOver audit remains V05. |

## Dependability and continuity

| ID | Priority/status | Open outcome / evidence |
|---|---|---|
| C01 | P0 awaiting hardware | Validate HR/RR/contact for both generations/firmwares and three placements; [checklist](HardwareValidation.md). |
| C02 | P0 open | Implement non-destructive firmware-bounded historical transfer/resume/retention behavior; [protocol boundary](ProtocolResearch.md). |
| C03 | P0 awaiting hardware | Validate suspension/restoration/restart/permission loss/competing connections and interruption gaps. |
| C04 | P1 awaiting hardware | Validate sequential switching, on-body versus charging evidence, manual preference and workout continuity. Concurrent connections remain unknown. |
| S01 | P0 awaiting hardware | Signed two-phone CloudKit restore, account changes, quota/network/deletion/conflict behavior; [sync](CloudKit.md). |
| S02 | P1 open | Background sync scheduling and silent push. |
| S03 | P0 open | Multi-year local compaction, bounded analytical caches, streaming backups and resumable schema migrations. |
| H01 | P1 awaiting hardware | Signed Health permission/export/import-loop and cross-source reconciliation checks. |
| H02 | P1 open | Health export updates/deletions and selectable source reconciliation policies. |

## Analytics and extensions

| ID | Priority/status | Open outcome / evidence |
|---|---|---|
| A01 | P1 open | Validated sleep detection/naps/timing consistency and richer imported interval reconciliation; preserve corrections. Staging remains unavailable. |
| A02 | P1 open | Full baseline-window placement/source audit and device/placement distribution calibration; [placement](WearingPlacement.md). No invented offsets. |
| A03 | P1 open | Full trends catalogue/custom ranges, nightly aggregation, journal pairing and uncertainty-aware associations. |
| A04 | P1 awaiting hardware | Evaluate HR-only activity suggestion false positives/misses at each placement; [rules](AutomaticActivity.md). |
| E01 | P2 awaiting hardware | Authoritative battery, verified haptics/alarm contracts; unsupported controls stay hidden. |
| E02 | P2 open | Opt-in routes, notification cooldowns/quiet hours, breathing sessions and supported cues. |
| V01 | P1 awaiting hardware | Signed install, widgets/Live Activities/privacy and Lock Screen behavior. |
| V05 | P1 awaiting hardware | iOS26 runtime, VoiceOver, large text, contrast/transparency, background/battery/performance audit. |

Original acceptance mapping and exact limitations: [KnownLimitations.md](KnownLimitations.md). These stay as accurate product documentation; this backlog is the work queue.
