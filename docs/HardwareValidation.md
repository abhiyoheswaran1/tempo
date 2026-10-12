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
