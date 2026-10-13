# Stored-band history and gaps

Live HR receipt and band-memory retrieval are separate. Neither wearing a band nor a current BPM proves that older measurements reached Tempo. Missing intervals remain visible; no interpolation supplies invented samples.

## Confirmed lifecycle

WHOOP5 on iOS first writes the documented145/revision1 Hello with response, then subscribes to protected fd4b0003/4/5/7 channels after write confirmation. A second145 request over subscribed channels reads application firmware. Only50.42.1.0 enables range34; its65 semantic bytes plus two zero padding bytes are parsed. A positive backlog starts22/body00. A write acknowledgement alone never establishes available history or verified encryption.

WHOOP4 subscribes to its documented channels, queries battery26/body00 then application version7. Only read-confirmed41.17.6.0 enables experimental22/body00. Standard DIS version text alone does not enable history. Layouts and metadata are generation-specific.

## Integrity and durability

Each notification channel has bounded CRC reassembly. Discarded bytes, unresolved fragments at END, malformed or partial chunks prevent acknowledgement. A chunk permits2MiB/10,000 data frames plus closing END. Source frames, decoded observations, rejected layouts and checkpoint commit atomically with WAL/FULL durability. Ordinary23 ACK is01 plus the exact original8-byte END token only after commit. W4 token starts17; independently evidenced W5 token starts21. Connection/session, transfer-attempt UUID and token guard asynchronous completion, preventing late commits from acknowledging a retry. Duplicate observations retain stable device/record-index/time identifiers across phones.

R18 primary HR is decoded on the named W5 firmware. Opaque quality/cardio flags remain retained; RR/temperature/SpO2/wear are not inferred from them. Unknown records stay raw where supported, rather than becoming guessed metrics. Unqualified R18 is excluded from physiological analytics, Health export and activity detection, while labelled charts and experimental possible-sleep proposals can describe its recorded HR. Older source observations remain immutable.

## Recovery and limits

History is requested on supported connection and foreground/manual checks, with15minute freshness. Started streams are not cut off by the ordinary20second reply wait; total transfer deadline remains120seconds. Timeout abort20 does not trim uncommitted data. After the250-sequence budget, Tempo reconnects automatically instead of reusing an unverified command sequence; committed data survives and unacknowledged chunks may replay. Reconnection and large multi-hour transfers still need overnight testing.

Sleep candidate analysis is coalesced2seconds after history commits, off the main actor, rather than delaying every incoming chunk. Cancelled/old-dataset analysis cannot publish results. iOS suspension and force-quit constraints still apply; Core Bluetooth does not guarantee uninterrupted execution. A finite background assertion protects storage, not continuous uptime.

ATT5/8/12/15 indicate protected-access failures. One normal fresh reconnect is attempted for a possible transient encryption race, with a2second session-scoped delay; persistent refusal is reported. The per-device budget resets after a committed history chunk. Normal OS pairing may be required; no firmware flashing, clocks, keys/certificates, read-pointer mutation, forced trim or authentication bypass are implemented.

## Physical evidence and retention

On2026-10-13, the owned WHOOP5/50.42.1.0 completed Hello, protected subscriptions, metadata, range and stored-record transfer after normal iOS pairing. SQLite inspection confirms historical R18 observations, raw frames and a checkpoint, with actual older timestamps preceding the diagnostic launch. This validates a transfer on this particular band, not all firmware, overnight coverage, analytical quality or all past gaps.

The returned range was recent; prior nights were absent. The reported trim-side time agreed with the returned start. Earlier offload/reclamation by another app is one possible explanation; available metadata does not prove every older flash page is recoverable. Do not promise unlimited retention or overwrite invasive cursors to recover already consumed history. For history available in Apple Health, optional sleep/workout/HR import is a separate provenance-labelled route; it depends on permission and actual Health records, not WHOOP cloud access by Tempo.

The original generic notification-first profile was refined using current public [iOS BLE lifecycle research](https://github.com/ryanbr/noop/blob/main/Strand/BLE/BLEManager.swift). No implementation or personal packet fixtures were copied into the repository. Temporary raw capture was private, bounded, opt-in and removed from the shipping code; ordinary health payload logging stays off.

## Overnight acceptance

Keep the band paired with Tempo and avoid a competing collector. Let the phone lock normally; do not force-quit Tempo. Reopen in the morning, refresh, then check actual older sample timestamps, last stored chunk and coverage. A possible-sleep estimate needs qualifying sustained HR and review; no stages are promised. Confirm timing accuracy and investigate remaining gaps before closing the overnight/background gates. Transfer COMPLETE is not proof of gap-free coverage.
