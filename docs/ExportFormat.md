# Tempo independent backup v1

UTF-8 JSON document. `format` is tempo-backup; `schemaVersion`1; `exportedAt` UTC Codable Date; `algorithmVersion` tempo-1.0; `payload` Base64 JSON bytes; `checksum` lowercase SHA-256 of exactly those payload bytes. Codable dates are seconds since Apple's2001 reference epoch; they represent UTC instants, not local clock times. Sleep/journal retain timezone identifiers.

Payload contains immutable observations and every revision (including parents, concurrent edits and tombstones). Observations include stable ID, portable device UUID, metric, UTC timestamp, value, origin, transport, RR intervals, quality, contact and optional algorithm version. Registry/workout/source/sleep/journal/activity-decision/placement data are typed revision payloads. Phone peripheral identifiers, Bluetooth bonds, Health anchors and CloudKit tokens/account credentials are excluded. Live HR's phone receipt time does not reconstruct a missing device clock.

Restore validates format/schema, checksum and256MiB decoded bound before inserting. Conflicting same-ID values are rejected; duplicate imports are idempotent. Records and outbox changes commit together in one transaction; error rolls back the import. Synthetic observations and synthetic sleep/workout/activity-decision revisions are rejected from real backup restore, even when an archive contains no measurements. Confirmed estimated workouts retain detection identity and algorithm version; candidates retain coverage and input digest. Other versions require a supported migration rather than best-effort reinterpretation.

Exports are plaintext, unencrypted and unauthenticated. SHA-256 detects accidental alteration; it is not a signature. Keep a separate secure copy; sync is not a backup. The current implementation builds an archive in memory and therefore is not suitable for multi-gigabyte exports. Streaming/chunked backups are required before multi-year high-frequency archives approach the v1 limit.

Placement revisions contain portable device ID, user-reported position, UTC effective instant and timezone ID. All correction ancestry is retained; measurements are not rewritten to attach position.
