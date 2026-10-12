# Physical validation — no completed hardware tests

Record generation, serial hash, full firmware versions, iPhone/iOS, Tempo commit, date and results. Do not record key/signature blocks or health payloads in routine logs.

1. Discover/register Whoop4 and Whoop5 separately, including generic HRS broadcast. Reject an unrelated heart-rate peripheral. Confirm registry survives relaunch and both identities remain present.
2. For each band verify HRS subscription, HR at rest and during exercise, contact supported/unsupported flags, RR cadence/units and malformed packet rejection. Compare with a trusted simultaneous reference; a plausible number is insufficient.
3. Disable internet; collect10minutes; relaunch and inspect stored timeline/export. Background/lock phone30minutes and measure actual coverage, then test Bluetooth off/on, range loss, competing app, permission denial, phone restart and force-quit. Expect gaps; do not promise execution after force-quit.
4. Wear one band with the other charging nearby. Confirm selector does not replace valid active data. Explicitly switch source during a workout: it remains one workout, segments change, pause elapsed seconds and gaps stay correct after relaunch. The one-connection transport cannot independently observe the unconnected band's wear; verify this limitation visibly.
5. Do not enable historical acknowledgement/trim. First establish a safe firmware-specific non-destructive offload sequence and clock validity. Obtain authorised redacted sensor captures, label exact record versions, validate CRC/timestamps/HR/RR, interrupted replay and ring retention. Unknown versions remain unavailable. Whoop4 v25 has no mapped HR; Whoop5 is not a shifted Whoop4 layout.
6. Provision private CloudKit on two signed phones. Compare immutable IDs, offline edits, concurrent manual corrections, logical deletions and interrupted restore. Repeat quota/network failure and Apple-account switch while upload is active; old history must not appear in another account.
7. Enable only selected Health permissions; deny each independently. Export/import HR twice, terminate mid-import, then resume. Delete an imported Health sample and confirm it no longer contributes. Overlapping external workouts/sleep must not sum; source policy must be visible.
8. Inspect Dynamic Type accessibility sizes, VoiceOver order/labels, light/dark, increased contrast, reduced transparency/motion, stale widgets and stale Live Activity. Verify Live Activity does not conceal stopped collection.

Haptics, alarms, motion-based sleep, calibrated temperature/respiration/SpO2, concurrent connections and full historical catch-up are not production-enabled. Parser tests and simulator UI tests prove none of those hardware behaviors.

## Experimental activity suggestions

1. Enable Activity detection, verify configured maximum HR, then collect a sustained activity with the phone connected. Keep an independent start/finish record.
2. After recovery, open Activity. Verify the suggested interval, source bands and coverage against collected HR; record false positives and missed activity. No sport should be inferred.
3. Correct the sport/times and confirm. Verify exactly one workout, estimated provenance and sensible coverage. Repeat scans and relaunch: no duplicate suggestion or workout.
4. Dismiss another suggestion; rescan and restore on the second phone. Verify dismissal persists. Record a manual overlapping workout and verify its suggestion disappears.
5. Repeat with a Bluetooth gap and a supported band switch; inspect disclosed gaps and source segments. No duration or load should be created from uncollected samples.
6. With explicit Health workout export permission, export a confirmed session twice: verify one Health workout with Tempo provenance, and verify Health import excludes Tempo's own export. Demo suggestions must never export or sync.

These steps validate behavior on owned devices; passing simulator tests does not establish detection sensitivity or accuracy.

## Three wearing positions

For both bands, repeat live HR/RR collection, a manual workout, potential-workout review and overnight coverage checks at wrist, upper arm and the designated underwear sensor pocket. Record each move in Tempo. Compare HR where practical against an independent reference and note fit/contact failures; do not infer temperature or oxygen availability from position. Move one band during a workout and verify one session with both placement contexts, without source-history reset. Restore reports on a second phone and verify its own Bluetooth pairing remains separate. Resolve concurrent report corrections and verify disputed periods show unknown until resolved.

Physical comparison is needed before claiming equal accuracy or adding placement-specific thresholds.

## Connection-feedback regression pass

Follow the concise [band controls, multiple-wear and foreground refresh procedure](BandManagement.md#physical-retest). Record actual firmware, placement, contact flags, notification timestamps, reconnect behavior, disconnect persistence, generation correction, history retention and signed cloud timestamps. Parser/state-machine tests and simulator captures do not close these physical checks.

## Collection UI retest

On each signed physical band, check Today → Band status → Live: source and connection must match the registered band; HR receipt, contact evidence, independent history transfer status and successful iCloud exchange must remain distinct. Disconnect explicitly, confirm live becomes recent then stale after90s, and confirm the main Live value becomes unavailable while retained history remains. Reconnect using the same portable identity; unknown contact must not turn into confirmed wear from pulse or proximity. Check large text/VoiceOver and denied Bluetooth/Health permissions. Removing registration must retain history in Trends while ending that band as a current Live source. Simulator cases do not validate any physical communication.

Battery check: for each generation/firmware, confirm whether a single180F/2A19 service is exposed, compare reported percent against a trusted device reading, check changes after use/charging, disconnect hiding, one-hour expiry and VoiceOver. A constant100 response must not be promoted to reliable battery capability.
