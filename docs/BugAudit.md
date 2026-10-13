# Integrity bug audit — 13 October 2026

Scope: local queries and immutable history, cloud manifests and retry races, historical transfer durability, source switching/workout chronology, Health import and UI regression flows. This is an audit of the available code and test environment, not certification of every acceptance criterion.

## Reproduced and repaired

| Finding | Cause and resulting behavior | Regression evidence |
|---|---|---|
| Requested metric omitted | Metric filtering happened after the newest-row limit. Query now filters kinds before limiting and backfills visible rows after tombstones. | Requested RHR survives newer HR rows; newest deletion does not consume visible limit; 4,096-row page boundary. |
| False live-chart gaps/truncation after deletion | Deleted records consumed the bounded window. Tombstones now participate in the single SQLite snapshot before LIMIT. Decoding can yield after the fetch, with no mutable OFFSET pagination. | Deleted newest record leaves the older visible reading and no false truncation; genuine excess visible rows still report truncation. |
| New manifest inherits old retry count | Replacing a dirty manifest reset its due time but retained attempts. New payload now resets both. | Failed batch followed by a new same-bucket observation starts at zero attempts. |
| Stale upload failure delays newer payload | Failure callback updated retry state by ID alone. It now matches the original manifest payload, as acknowledgement already does. | In-flight old failure cannot defer the changed manifest. |
| Malformed timestamp crash | Finite but unrepresentable timestamps reached an unchecked integer conversion. Insert rejects them before enqueue and rolls back the complete write; non-finite timestamps are not valid observations. | Extreme timestamp test reproduced a process trap before the fix; valid prefix rolls back afterward. |
| Backward workout chronology | Source switches or finish times before prior events could create negative intervals. Invalid chronology is rejected; a rejected finish leaves the workout active and reports the clock problem. | Earlier source switch/finish, active pause, and closed source end cases. |

The reproducer regressions failed before their respective fixes. Follow-up boundary tests protect pagination, genuine truncation and pause/source chronology. An independent read-only review found a stale-failure race during the first review; it was reproduced and fixed. The second review found no remaining critical/important defects in the changed lines.

## Remains open

- C05/C02: missing overnight and some afternoon HR periods were absent from returned band records. These fixes do not reconstruct absent measurements.
- C03/D05: physical background recovery, smooth scrolling under live receipt/catch-up and CPU-resource termination require device retesting and profiling.
- S01/H01: signed multi-phone CloudKit restore/account/permission behavior and Health source reconciliation require physical validation.
- A05: Health sleep import currently retains stage intervals separately; continuous-night reconciliation with source provenance and manual-edit priority remains unfinished.
- S03: multi-year compaction, streaming backup and larger-history analysis remain separate volume work.

Latest run counts and installation results are maintained in [Verification.md](Verification.md); open acceptance gates are in [Improvements.md](Improvements.md).
