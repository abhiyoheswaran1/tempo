# Tempo active improvements

Single working backlog. Update when scope changes or evidence closes an item. Priorities: P0 integrity/collection, P1 continuity/usefulness, P2 polish/extensions. Status: open, in progress, or awaiting hardware. Remove a ticket only after its acceptance checks pass; append one compact line to [Completed](Completed.md). Durable contracts belong in the linked technical docs, not duplicated ticket prose. Git retains superseded plans and detailed investigation history. Never delete unresolved findings or treat compilation as physical validation.

## Further interface work

| ID | Priority/status | Open outcome / evidence |
|---|---|---|
| D01 | P1 awaiting hardware | Exact QuartzCore message reproduced in independent minimal NavigationStack app without BLE/cloud; [evidence](RenderingDiagnostics.md). Confirm physical OS/action and any freeze/flicker/crash before an app workaround. No log suppression or fixed claim. |
| D02 | P1 awaiting physical validation | CFPrefs App Group diagnostic: local signed app/widget groups match signatures and provisioning; user confirms signed phone widget timestamp updates (2026-10-12); warning persists without a reported timestamp-sharing failure. Verify other summary fields/relaunch under V01. No group renaming to suppress logs. |
| D03 | P1 awaiting physical validation | PointerUI non-launching-port diagnostic: check minimal native/runtime logs, distinguish input service from BLE/cloud and retain physical OS/failure boundary. |
| UX18 | P1 in progress | Header battery percentage only for an actually exposed supported battery feed; reject malformed/stale data, disclose unavailable BAS and preserve physical E01 gate. |
| UX19 | P1 in progress | Drastic Today hierarchy: live hero, useful daily summaries, compact readiness/baseline and quiet sync/refresh; reduce per-reading render work, preserve missing/stale/provenance and accessible controls; fresh captures. |
| UX16 | P2 open | Fast journal: energy/soreness/mood first, optional behaviours afterwards, Today check-in completion with Edit; unknown answers stay unknown. Routine check-in under 30 seconds requires usability validation. |
| UX09 | P2 open | Session-detail progressive disclosure: make notes/exertion easier to reach and reduce repeated unavailable fields in empty workout summaries. Keep coverage/source evidence inspectable. |

UX01–UX08 and UX10 are closed in [Completed.md](Completed.md). Physical audit V05 stays open.

Band feedback B01–B06 is implemented and software-verified in [Completed.md](Completed.md). The [connection/live/refresh contract](BandManagement.md) includes physical retest steps; C01/C03/C04/S01 remain open.

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
