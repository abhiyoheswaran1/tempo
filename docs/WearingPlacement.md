# Wearing placement

Research and implementation: 2026-10-12. Tempo supports user-reported wrist, upper-arm/bicep, and underwear/WHOOP Body placement independently for each registered Whoop 4 or Whoop 5. The underwear label refers to the sensor pocket/contact location in compatible apparel, not any arbitrary location inside clothing.

## Evidence and boundaries

- [WHOOP Body](https://www.whoop.com/us/en/thelocker/whoop-body-wearable-technology-future/) describes tested off-wrist apparel positions and sensor contact. This manufacturer evidence does not validate Tempo's collection or analytics.
- [WHOOP Steps](https://support.whoop.com/s/article/Steps?language=en_US) says step tracking is optimized for wrist wear.
- [WHOOP Strength Trainer](https://www.whoop.com/us/en/thelocker/introducing-strength-trainer-a-new-way-to-quantify-the-impact-of-your-strength-training/) (May 20, 2026) explicitly requires wrist movement for its current motion algorithms.
- [WHOOP signal-quality discussion](https://www.whoop.com/us/en/thelocker/what-are-the-best-pulse-points/) describes how fit, contact and body location affect optical measurements.
- The reviewed [public command reference](https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_COMMANDS.md) does not establish an implemented, validated placement read/write contract for Tempo's transport. No placement commands are transmitted. Absence from this review does not prove firmware lacks such behavior.

Placement can change signal quality and motion patterns. Public sources do not reveal a complete separate proprietary health/recovery algorithm for every position. Tempo reads band-reported HR/RR where supported; it does not possess the raw optical pipeline or reproduce WHOOP firmware processing. RMSSD/SDNN definitions and cardiovascular zone formulas are unchanged by a placement label. No invented bpm, HRV, temperature or oxygen correction is applied.

## Using Tempo

Settings → Manage and reconnect bands → select a band → Record wearing placement. Tap a current position whenever you move the sensor. Record an earlier change with an effective time if necessary. Tap a history entry to correct its context. Mark placement unknown if uncertain. Each band's history remains independent; a second band's position never overwrites the first.

Records are manual context. They remain in effect until the next report for that band; Tempo cannot know about unreported movement. Older measurements before the first report stay unknown. Contradictory reports at the same effective instant resolve to unknown rather than arbitrary last-write-wins. Concurrent edits of the same record use the normal revision-conflict workflow.

UTC effective instants plus timezone identifiers preserve travel/DST presentation. Placement is stored as immutable revision ancestry, included in normal sync/export/restore, and not embedded into immutable measurements. Correcting a report can update a session's displayed context without changing its measured values. Sync uses existing encrypted revision payloads; no new CloudKit record type is required.

## Analysis

Workout and sleep details associate reports with actual valid band measurements by portable device ID and timestamp. Imported measurements are not assigned a Whoop placement. No corresponding measurements means no placement evidence, rather than assuming the currently selected band was worn during that session.

Readiness v1.1 flags more than one known reported placement within available measured overnight samples for qualifying sleeps. Confidence is multiplied by0.75, a conservative unvalidated product heuristic, without changing the score or deleting/resetting baseline inputs. This is not a quantified accuracy estimate. The current in-memory measurement window is two days; this comparison cannot audit placement differences throughout the full28-day history. Unknown positions are omitted from the change test and remain visibly unknown in detail. Full per-placement distribution calibration remains future work requiring adequate observations.

The experimental HR-only workout detector applies the same documented thresholds at all positions. This permits suggestions with supported HR at each placement but does not demonstrate equal detection accuracy. Motion-derived steps, rep counting and muscular load remain unavailable; they need their own placement-specific validation.

## Validation

Software tests cover timestamp boundaries, per-band separation, contradictory reports, idempotent archive restore, immutable measurement preservation and confidence behavior. Simulator tests exercise reporting all three locations and retaining prior entries. Physical validation is required for contact quality, supported HR/RR streaming, false/missed workout suggestions, overnight coverage and comparison with an independent reference at each position. Do not claim automatic location recognition or equivalent measurement accuracy from these software tests.
