# Tempo active improvements

Single working backlog. Update when scope changes or evidence closes an item. Priorities: P0 integrity/collection, P1 continuity/usefulness, P2 polish/extensions. Status: open, in progress, or awaiting hardware. Remove a ticket only after its acceptance checks pass; append one compact line to [Completed](Completed.md). Durable contracts belong in the linked technical docs, not duplicated ticket prose. Git retains superseded plans and detailed investigation history. Never delete unresolved findings or treat compilation as physical validation.

## Further interface work

| ID | Priority/status | Open outcome / evidence |
|---|---|---|
| C05 | P0 awaiting overnight validation | Owned Whoop5/50.42.1.0 now physically completed protected pairing, range, historical R18 retention/checkpoint and transfer completion. Earlier nights absent from returned recent range; no unlimited retention claim. Validate tonight's recovered coverage, timestamps and sleep proposal after normal lock/background operation; [contract](HistoryRetrieval.md). Personal captures remain private. |
| D01 | P1 awaiting hardware | Exact QuartzCore message reproduced in independent minimal NavigationStack app without BLE/cloud; [evidence](RenderingDiagnostics.md). Confirm physical OS/action and any freeze/flicker/crash before an app workaround. No log suppression or fixed claim. |
| D02 | P1 awaiting physical validation | CFPrefs App Group diagnostic: local signed app/widget groups match signatures and provisioning; user confirms signed phone widget timestamp updates (2026-10-12); warning persists without a reported timestamp-sharing failure. Verify other summary fields/relaunch under V01. No group renaming to suppress logs. |
| D03 | P1 awaiting physical validation | PointerUI non-launching-port diagnostic: check minimal native/runtime logs, distinguish input service from BLE/cloud and retain physical OS/failure boundary. |

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
| A01 | P1 open | Experimental HR-only possible-sleep detection/review is implemented; validate owned-band timing, quiet-wake/charging false positives and missing-data rejection. Motion-backed automatic detection, naps/timing consistency and richer imported reconciliation remain open; staging unavailable. |
| A05 | P1 open | Health sleep import currently retains separate stage intervals as separate sessions. Reconcile continuous nights with source provenance and manual-edit priority before treating fragmented imports as complete sleep; real Health permissions/source cases required. |
| A02 | P1 open | Full baseline-window placement/source audit and device/placement distribution calibration; [placement](WearingPlacement.md). No invented offsets. |
| A03 | P1 open | Full trends catalogue/custom ranges, nightly aggregation, journal pairing and uncertainty-aware associations. |
| A04 | P1 awaiting hardware | Evaluate HR-only activity suggestion false positives/misses at each placement; [rules](AutomaticActivity.md). |
| E01 | P2 awaiting hardware | Authoritative battery, verified haptics/alarm contracts; unsupported controls stay hidden. |
| E02 | P2 open | Opt-in routes, notification cooldowns/quiet hours, breathing sessions and supported cues. |
| V01 | P1 awaiting hardware | Signed install, widgets/Live Activities/privacy and Lock Screen behavior. |
| V05 | P1 awaiting hardware | iOS26 runtime, VoiceOver, large text, contrast/transparency, background/battery/performance audit, including real journal check-in timing under30seconds. |

Original acceptance mapping and exact limitations: [KnownLimitations.md](KnownLimitations.md). These stay as accurate product documentation; this backlog is the work queue.

| D05 | P0 open | Investigate physical CPU resource termination. A prior device log reported 99% CPU over 146 seconds; a later 60-second profiler capture still showed substantial SwiftUI AttributeGraph work. Release optimisation and coalesced analysis are implemented, but sustained foreground/background reliability is not yet established. Acceptance: overnight collection without CPU termination and measured live-chart/background CPU checks. |
