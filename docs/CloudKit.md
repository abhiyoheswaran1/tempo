# Private CloudKit setup and behavior

Tempo uses the signed-in Apple account's private database and a custom `TempoHistory-<account-hash-prefix>` zone. No separate login/backend. Sync defaults off; local collection is independent. Enable in Settings after provisioning the container.

## Schema

In CloudKit Console select the configured container and Development environment. Save initial data from the signed app to create the zone/type. Ensure record type `TempoPayload` has:

| Field | Type | Purpose |
|---|---|---|
| kind | String | batch or revision, no sensor values |
| schemaVersion | Int64 | current1 |
| payload | Encrypted Bytes | LZFSE-compressed Codable SyncEnvelope |
| checksum | String | SHA-256 of compressed bytes |

`payload` is written through `CKRecord.encryptedValues`, not ordinary `record[]`. Do not configure it as a plain Bytes field. If auto-created development schema differs, inspect the console and resolve before provisioning a second phone. A personal development installation can use Development; a distribution-signed build uses Production and needs Deploy Schema Changes. Record-name IDs do not require an app-wide public query index: download uses zone changes.

## Durability and conflicts

15-minute UTC sensor buckets per portable device, bounded by4MiB decompressed and800KiB compressed upload maximum. No per-sample CloudKit records. Dirty manifests are in SQLite; sample writes and dirtiness commit atomically. Upload merges existing remote batch observations by immutable ID, retaining conflicts as errors rather than silently overwriting values. CK save policy checks server change tags. An upload only acknowledges the queued payload version it read, preventing loss of samples arriving during upload.

Activity candidates and their confirmation/dismissal decisions use the same revision transport as workouts; no separate cloud schema is required. Synthetic revisions are rejected by real-store ingestion.

Manual edits are separate immutable revision records, parent IDs define ancestry. Concurrent heads are retained and shown in Settings. Logical deletions are tombstone revisions and propagate through normal uploads. Raw observations are retained for audit/export; Health-deleted observations are excluded from analytical reads. Physical remote record deletion and zone purge are not app operations; deletion made directly in CloudKit Console is not interpreted as a user health-history deletion.

Downloads use persisted zone-change tokens, advancing only after all page records commit. Expired token triggers a fresh replay once. Interrupted pages replay idempotently. Durable retries use exponential delay capped6h or server retry-after. Quota/network failures preserve local outbox entries. Sync currently runs on explicit action and app activation; silent push/BGTask scheduling is not implemented, and background mode alone does not guarantee sync.

## Account isolation

The local dataset binds to a hash of the current user-record name when sync is first explicitly enabled. Later identity mismatch blocks transfer and token use. Return to the original account to resume. This build does not provide an automatic destructive “reset account” operation. Keep separate app/container configurations for an intentionally separate dataset. The zone name is account-namespaced; user-record identity is checked at network boundaries. Account-change notifications pause in-flight work; test actual account transitions before relying on isolation. A successful pure AccountGate unit test is not CloudKit integration validation.

## Restore checklist

Install same configuration on a second iPhone using same Apple account. Enable sync, wait for restore, confirm registry, immutable observations, workouts, sleep and edits. Explicitly match each physical band to its restored identity. Compare backup observation IDs across phones; reconnecting must not generate a new history identity. Make conflicting offline sleep edits and resolve the preserved heads. Deny network / fill quota and confirm collection still persists locally.

## Encryption

Sensitive payloads use CloudKit encrypted fields and private database permissions. Local SQLite protection is completeUntilFirstUserAuthentication, needed for supported background access after first unlock. Apple manages iCloud credentials; Tempo stores no cloud passwords/API keys. Backups are plaintext JSON and require secure handling. This implementation makes no end-to-end encryption claim; protection depends on CloudKit semantics, account settings and platform conditions.
