# Connection, wearing and automatic refresh

Tempo keeps these concepts separate:

- **Registered:** a portable identity with retained history, independent of phone-specific Bluetooth identifiers.
- **Nearby:** a recently discovered advertisement, not a connection or proof of wear. Discovery is limited to the service filters and broadcast/pairing modes the band exposes; Tempo cannot list every band in radio range.
- **Connected:** Core Bluetooth has reported a connection. A connection can exist without heart-rate notifications.
- **On-body reported / Off-body reported:** a valid, at-most-90-second-old connected Heart Rate Service sample supplies a supported contact flag. Absent contact support, the interface says **Wear not reported** (the internal state remains unknown). This does not mean the band reports off-body. Contact accuracy at wrist, arm and underwear still requires hardware validation.
- **Selected source:** the band used for the canonical timeline and live workout. Manual placement reports are context, not proof of wear.

One connection is maintained until concurrent-band behavior is validated. Consequently, an unconnected nearby band cannot have its current wear status verified. If both bands supply usable evidence, automatic selection retains the active usable source. No overlapping activity is summed. The core selector uses90-second sample freshness,60-second disconnection grace and30-second candidate stability. A sequential fallback probe is rate-limited to once per180seconds. Charging/off-body evidence disqualifies a source; proximity does not qualify it. These are software policies, not verified hardware outcomes.

## User controls and identity

Connect is idempotent while a request is pending or a band is connected. Disconnect suspends automatic reconnection for that band on this phone, including after app relaunch. Tap Connect to resume. A temporary link interruption preserves connection intent and requests reconnection through Core Bluetooth. State restoration is configured; actual suspension/termination behavior remains a physical test.

Remove band writes a registry deletion revision and stops local collection. Physiological observations, workouts and source history are retained. A removed identity can be restored through the discovery registry-match picker. Match a physical band explicitly on another phone; names do not prove identity and CloudKit does not restore Bluetooth bonds. Remapping to a different peripheral while connecting/connected/disconnecting is rejected to prevent delayed callbacks stranding the replacement connection.

Generation is determined only from an exclusive known Whoop4/5 service advertisement or discovered service. Unknown generation requires explicit confirmation; ambiguous services are not guessed. An existing incorrect generation can be corrected in band details, preserving identity and observations. Only default names are renamed automatically; custom names are retained.

## Why HR can work while wear is not reported

The current production adapter subscribes to standard Heart Rate Service. Its contact-support bit is optional; if absent, Tempo receives pulse measurements without a wear assertion. A live plausible pulse is usable physiological evidence, not a substituted contact flag. The interface shows “Receiving heart rate” and “Wear not reported” separately; the status sheet and dashboard explain this distinction.

Current community documentation describes proprietary command84, but that is not implemented in Tempo's production transport. Whoop4 has a firmware-bounded legacy response; Whoop5/MG50.42.1.0 has a revisioned cached-status reply with fixed location/confidence placeholders. Firmware identity, link setup, response/result correlation and physical interpretation need validation before enabling it. No wear override command is sent, no status is fabricated, and the Whoop5 placeholders cannot identify wrist/arm/underwear. See [protocol notes](ProtocolResearch.md).

## Live dashboard

The dashboard shows direct heart rate, a four-hour canonical chart with 15-minute/one-hour options, covered-time average, observed range, covered time, estimated zone, source/contact status, latest supplied R–R intervals and workout controls. A connected sample no older than10seconds is labelled live; up to90seconds is recent, and older readings are stale. Repeated display of an old number is not labelled a live stream. Chart gaps over10seconds are disconnected; load excludes those intervals. Latest intervals are not an overnight HRV result. Unsupported oxygen and temperature remain unavailable. Optional battery reports follow the bounded standard-service policy in ProtocolResearch; absent reports stay unavailable.

## Automatic refresh and timestamps

On foreground activation (including return from background), Tempo resumes the intended connection unless explicitly disconnected, reevaluates fallback and refreshes its sync summary. Cloud sync is requested when the last successful pass is at least five minutes old, never succeeded, or changes are pending. Automatic attempts are limited to once per60seconds; CloudKit failures defer another pass by at least60seconds or the server's longer retry hint. Durable outbox entries retain their own retry schedules. Explicit Retry can request a new attempt. Quiet collection callbacks also request a coalesced15-second status refresh; they may request a due sync subject to the same cooldown. This does not keep iOS awake or guarantee periodic background execution. Silent push/background sync scheduling remains open.

Today now places the live dashboard directly below readiness, beside an accessible Refresh control. Pull down on Today invokes the same action: reload local history, resume existing connection intent (respecting explicit disconnection), and request a cloud pass when enabled. Manual refresh bypasses the five-minute automatic freshness gate while respecting service/outbox backoff. It does not promise new sensor notifications or historical retrieval. Inline results distinguish demo/local-only, a successful new cloud pass, running sync, errors, pending retries and a scheduled retry; an old successful timestamp cannot masquerade as a new sync. Concurrent Today refresh requests coalesce.

Today, the band status sheet and settings show **last successful iCloud sync**, pending uploads and actionable errors. **Last reading** is separate. Historical retrieval timestamps remain unavailable until supported transfer is implemented; reopening the app cannot manufacture a successful band-history sync. No complete proprietary historical retrieval is currently enabled.

Demo uses a separate memory database and never instantiates sync for that dataset. Async sync continuations validate the original database identity before starting or refreshing the interface.

## Physical retest

1. Register each actual band. Verify Whoop5 stays Whoop5 and correction preserves its existing history.
2. While connected, scan again; the band must not appear as a new actionable registration. Verify actual HR notifications and timestamp advance.
3. Keep the selected band worn while another charges. Observe wear flags at each placement; unknown must remain unknown when unsupported.
4. Wear both bands; selected usable source must not oscillate. Current one-connection transport cannot validate wear of both concurrently.
5. Interrupt Bluetooth briefly, return from background and verify reconnection. Disconnect explicitly, relaunch and confirm no reconnection until Connect.
6. Remove and restore a band identity; previous observations/workouts remain. Test interrupted matching without a permanently connecting row.
7. With your configured CloudKit container, return from background after six minutes; inspect last successful sync, pending changes and retry behavior offline/online. Test on two signed phones.

No simulator test is evidence that either physical band passed these checks.

## Refined collection surfaces

The Today band control reports the selected/last registered source with receiving/recent/stale status and receipt age. Current reception requires a valid direct HR reading no older than10s and a connection to that source, without fresh off-body evidence. Recent means at most90s, not confirmed live. Wear/contact evidence remains a separate field in the full-height band-status sheet; neither connection nor pulse supplies an invented wear report.

The sheet offers explicit per-band reconnect/disconnect, placement/details and collection diagnostics. iCloud's last successful exchange and pending uploads are separate from HR receipt. **Band history retrieval is unavailable in this build**, so Tempo does not label a live callback as a successful historical sync. A new phone still needs an explicit physical-band match through Manage and reconnect bands.

Live centres on current/recent HR and the five-minute chart. A stale pulse moves into a labelled last-recorded line and leaves the current reading unavailable. Covered-time average/range exclude gaps; source, timestamps, optional R–R and unsupported-sensor limits remain inspectable. Source/archive handling and signed physical collection still require the existing gates.

Live now defaults to four hours of locally stored direct band HR, with15-minute/one-hour options. A bounded40,000-record query filters HR/origin before its limit and yields while decoding. Up to960 original first/last/min/max points are plotted; gap series are computed before reduction, isolated readings have point marks, and statistics use all qualifying canonical inputs. Query failures, truncation and missing readings remain explicit. Refresh occurs on the visible screen at20-second intervals; this is not a background-execution promise.

The powered-state fix guards central stop/cancel/connect/scan commands and defers restoration work until powered on. Demo suspension cannot revive a restored connection. Reset/unsupported/permission failures invalidate peripheral handles. [Apple’s central-state contract](https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanagerdidupdatestate(_:)) supports these guards. Exact origin of the owner's warning was not captured; identified unsafe paths are corrected, while physical lifecycle validation remains C03.

Battery parsing, rate limits, freshness and hardware boundary: [ProtocolResearch](ProtocolResearch.md#optional-standard-battery-report).
