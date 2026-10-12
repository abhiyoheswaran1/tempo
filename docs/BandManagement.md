# Connection, wearing and automatic refresh

Tempo keeps these concepts separate:

- **Registered:** a portable identity with retained history, independent of phone-specific Bluetooth identifiers.
- **Nearby:** a recently discovered advertisement, not a connection or proof of wear. Discovery is limited to the service filters and broadcast/pairing modes the band exposes; Tempo cannot list every band in radio range.
- **Connected:** Core Bluetooth has reported a connection. A connection can exist without heart-rate notifications.
- **On-body reported / Off-body reported:** a valid, at-most-90-second-old connected Heart Rate Service sample supplies a supported contact flag. Absent contact support, wear is unknown. Contact accuracy at wrist, arm and underwear still requires hardware validation.
- **Selected source:** the band used for the canonical timeline and live workout. Manual placement reports are context, not proof of wear.

One connection is maintained until concurrent-band behavior is validated. Consequently, an unconnected nearby band cannot have its current wear status verified. If both bands supply usable evidence, automatic selection retains the active usable source. No overlapping activity is summed. The core selector uses90-second sample freshness,60-second disconnection grace and30-second candidate stability. A sequential fallback probe is rate-limited to once per180seconds. Charging/off-body evidence disqualifies a source; proximity does not qualify it. These are software policies, not verified hardware outcomes.

## User controls and identity

Connect is idempotent while a request is pending or a band is connected. Disconnect suspends automatic reconnection for that band on this phone, including after app relaunch. Tap Connect to resume. A temporary link interruption preserves connection intent and requests reconnection through Core Bluetooth. State restoration is configured; actual suspension/termination behavior remains a physical test.

Remove band writes a registry deletion revision and stops local collection. Physiological observations, workouts and source history are retained. A removed identity can be restored through the discovery registry-match picker. Match a physical band explicitly on another phone; names do not prove identity and CloudKit does not restore Bluetooth bonds. Remapping to a different peripheral while connecting/connected/disconnecting is rejected to prevent delayed callbacks stranding the replacement connection.

Generation is determined only from an exclusive known Whoop4/5 service advertisement or discovered service. Unknown generation requires explicit confirmation; ambiguous services are not guessed. An existing incorrect generation can be corrected in band details, preserving identity and observations. Only default names are renamed automatically; custom names are retained.

## Live dashboard

The dashboard shows direct heart rate, a five-minute source-specific chart, covered-time average, observed range, covered time, estimated zone, source/contact status, latest supplied R–R intervals and workout controls. A connected sample no older than10seconds is labelled live; up to90seconds is recent, and older readings are stale. Repeated display of an old number is not labelled a live stream. Chart gaps over10seconds are disconnected; load excludes those intervals. Latest intervals are not an overnight HRV result. Unsupported oxygen, temperature and battery values remain unavailable.

## Automatic refresh and timestamps

On foreground activation (including return from background), Tempo resumes the intended connection unless explicitly disconnected, reevaluates fallback and refreshes its sync summary. Cloud sync is requested when the last successful pass is at least five minutes old, never succeeded, or changes are pending. Automatic attempts are limited to once per60seconds; CloudKit failures defer another pass by at least60seconds or the server's longer retry hint. Durable outbox entries retain their own retry schedules. Explicit Retry can request a new attempt. Quiet collection callbacks also request a coalesced15-second status refresh; they may request a due sync subject to the same cooldown. This does not keep iOS awake or guarantee periodic background execution. Silent push/background sync scheduling remains open.

The band status sheet and settings show **last successful iCloud sync**, pending uploads and actionable errors. **Last reading** is separate. Historical retrieval timestamps remain unavailable until supported transfer is implemented; reopening the app cannot manufacture a successful band-history sync. No complete proprietary historical retrieval is currently enabled.

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
