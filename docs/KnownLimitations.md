# Acceptance status and remaining work

Tempo is not yet certified against the user's daily-use acceptance criteria. These are explicit gaps, not simulated successes.

## Implemented and verifiable in software

Native app/extension targets; SQLite actor and WAL/FULL transactions; duplicate history IDs; local registry with phone-specific peripheral mappings; standard HRS parsing and notification transport; separate firmware-gated proprietary envelope parsers; transactional checkpoint API; source hysteresis with charging/off-body exclusion; canonical overlap projection; persistent manual workout pause/relaunch/source segments; manual/imported sleep with revisions; optional journal; transparent conservative RR/readiness/load algorithms; source-change confidence reduction; bounded daily trend reads; private CloudKit bounded encrypted payload adapter/outbox/tokens/merge/conflicts/account binding; versioned checksummed backup; optional granular Health imports and measured HR/manual sleep/workout exports; summary widget and workout Live Activity; isolated labelled demo.

Portable preferences sync as revisions; Bluetooth connection state stays local. Foreground/event-driven fallback may try another registered band after interruption, with a3minute probe cooldown. One active connection is the default; unconnected-band wear cannot be independently evaluated.

## Requires owned-band and signed-phone validation

- Discovery/broadcast availability, live HR/RR/contact behavior and reliability on both generations and each firmware.
- On-body vs charging interpretation, physical source changes, background coverage, interruption recovery and bond/competing-app behavior.
- Actual CloudKit provisioning/schema, encrypted-field behavior, two-phone restore, quota errors, account changes during operations and Health permissions/duplicate export semantics.
- iOS26 runtime testing (installed tooling/runtime here is27), Lock Screen widget/Live Activity behavior and assistive-technology checks.

## Remaining protocol/collection implementation

- Full history session negotiation/recovery is not production-enabled. Whoop4 decoder/checkpoint components exist but no complete transfer is claimed. The documented acknowledgement can permit reclamation, and is excluded under the prohibition on destructive commands. A safe completion policy must be established before implementing unattended backfill.
- Whoop5 history/overnight layouts, calibrated physiological fields and firmware identity boundaries require instance evidence before enabling.
- Battery, proprietary wear, haptic effects and firmware alarms are hidden/unavailable. No firmware writes, authentication bypass, destructive opcodes or sensor probing.
- Concurrency across two band connections and automatic discovery of the unconnected worn band are unverified. Source preferences/temporary override and sequential reconnect paths are available.

## Remaining product/software work

- Motion-backed automatic sleep detection, sleep timing consistency and naps detection; current sleep is entered/imported. Detailed staging is intentionally unavailable.
- Device-specific distribution offsets and calibrated confidence models; source changes conservatively halve readiness confidence.
- Rich nightly aggregation/stage-interval merging; imported sleep intervals are retained, but conservative overlap projection can exclude an overlapping interval rather than reconstruct a full night.
- Custom trend ranges and full trend catalogue; current charts cover measured/imported metrics and entered sleep over7/28/90days. Personal association engine exists, but journal-to-metric pairing/insight presentation is not connected.
- Optional route recording, notifications/quiet-hours policies, breathing sessions and haptic timers/cues. These were not substituted with mock functions.
- Background CloudKit scheduling/push subscription; sync currently runs on activation/manual action. Health imports are bounded1000-record pages per type; repeat import to continue. HR export is bounded500 samples per action. Health export deletion/update reconciliation remains limited; app history deletion does not automatically delete Health exports.
- Large-volume optimization: sample rows are durable JSON and may reach30–80MB/day; compressed sensor buckets apply to cloud traffic. Local high-frequency compaction, streaming multi-gigabyte backups and richer cached analytical summaries are required before multi-year ingestion. UI range reads are bounded and unknown raw streams are not collected.

## Acceptance mapping

1/8: registry and explicit restored-device matching implemented; physical validation pending.
2/6: storage/offline path tested; real radio reliability pending.
3/5: selector/workout software tested; actual switching constrained by one connection and hardware evidence.
4/9/10/11: overlap/corrections/missing-input behavior and explanations implemented with regression tests; richer session aggregation remains.
7/12: CloudKit/Health adapters compile; actual account/data integration validation pending.
13: native adaptive layout and simulator interaction tests; full accessibility/device audit pending.
14: no required Whoop/cloud/backend account path.
15: limitations and validation procedure documented.

## Experimental automatic activity

Opt-in heart-rate-based potential workouts support confirmation, timing/type edits, dismissal and durable decisions. They do not classify sports or match WHOOP detection. Rules are software-tested; physical accuracy and background input coverage are unverified. See [methodology](AutomaticActivity.md).

## Wearing placement

Wrist, upper-arm and underwear reports are implemented per band with effective timestamps and revision-backed corrections. They are user context, not device-detected location. Placement-specific offsets, full baseline-window comparability auditing, motion classification and raw optical calibration remain unimplemented/unvalidated. Conflicting reports project to unknown. See [WearingPlacement.md](WearingPlacement.md).

## UI refinement verification boundary

Compact Today/evidence categories, band/placement sheet, native cross-tab workout controls, finish summaries and daily trend aggregation are implemented. Live dashboard, disconnect/removal with retained history, generation correction and separate sync/reading timestamps are implemented. Foreground activation checks connection intent and cloud freshness (five minutes or pending changes), with a60-second automatic attempt cooldown. Maximum Dynamic Type/dark-mode simulator checks and ten actual screenshots accompany this pass. Signed installation, physical VoiceOver/contrast/transparency/battery behavior and iOS26 runtime checks remain open in the improvement tracker. A native app target/workspace is included; the root Swift package is a non-executable library.
