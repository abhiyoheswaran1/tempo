# Architecture and decisions

Tempo is an independent personal wearable companion centred on local collection, durable history and transparent analytics. Multi-band registration and switching are features within that broader product, not its sole purpose. Public documentation describes interoperability and personal builds without presenting the project as a replacement for a manufacturer service.

Tempo targets iOS 26. No third-party packages. Swift Package TempoCore is testable without Bluetooth or iCloud; the app owns platform services on MainActor, SQLite is actor-owned, and sync operations are serialized.

SQLite rather than SwiftData: explicit transactions atomically store observations, retrieval checkpoints and outbox entries; uniqueness prevents replay duplication; SQL indexes allow bounded range reads. WAL with FULL synchronous durability. The database uses complete-until-first-authentication file protection on iPhone for supported background collection. This is availability/security tradeoff, not application-level encryption.

Portable registry UUIDs are separate from installation-specific peripheral mappings. Restored devices require explicit reconnection; a name never establishes identity. Hardware serial hashes can establish portable identity once confirmed. Unknown serials require user matching.

Observations are immutable. Historical IDs use portable device ID and validated record identity; live timestamps are phone receipt times and cannot promise cross-phone deduplication at subsecond precision. Canonical bins retain all source observations but choose one valid source. User corrections are immutable events with parent revision; concurrent corrections remain visible for resolution.

Sensor batches are bounded to 15-minute UTC buckets and compressed for CloudKit. At 1 Hz, compact HR data is approximately 1–4 MB/day including RR and overhead; SQLite JSON records and indexes may be 30–80 MB/day. Raw PPG/100 Hz IMU can exceed hundreds of MB/day and are deliberately not enabled. The current live collection stores HR/RR only. Summaries are computed from bounded reads. Diagnostics contain counts/status only and no payloads.

CloudKit is independent of collection. Private custom zone; durable outbox and incremental server token; account namespace binding; explicit enablement binds previously local data to the current account only once. A subsequent account change blocks sync until the original account returns or a separate empty local dataset is selected. No automatic cross-account history transfer.

Demo is a separate in-memory/separate-path dataset and platform integrations are disabled. App suspension and force-quit are iOS constraints. Background BLE restoration improves reconnection but cannot guarantee continuous execution.

Latest integrity refinements: normal database instances reject synthetic inputs; demo transitions serialize and suspend transport. Local edit appends compare expected parent heads inside the SQLite transaction. Workout source changes and pause/finish share a mutation queue. Immutable Health sample UUID provenance survives backups/cloud restore for deletion lookup. Recent range reads cap100,000 observations; daily representative queries cap366 rows; nightly projections cache by input coverage and algorithm version. Portable preferences are immutable revisions; sync opt-in stays installation-local. Foreground/event-driven sequential fallback is opportunistic, never a promise of background execution.

## Activity suggestions

A pure core detector consumes canonical measured HR and outputs versioned candidates with input digest, source IDs and coverage. AppModel serializes bounded recent scans and user decisions through the mutation queue. Candidates and decisions use immutable revisions and deterministic identities, enabling sync/backup replay. Confirmation persists a deterministic workout before marking its decision confirmed; interrupted confirmation is repaired on the next scan. Pending suggestions never count as workouts. Manual/imported overlapping sessions suppress proposals. Synthetic revisions are validated both on save and transactional archive import.

## Wearing placement context

Placement reports are separate immutable revision entities keyed to portable device IDs and UTC effective instants. They are user-entered metadata; transport and measured values remain unchanged. A pure projection retains conflicted reports as unknown boundaries, avoiding fallback to a formerly known position. Session context joins actual valid measured samples to the per-device report timeline. Known overnight position changes reduce readiness confidence through an explicit versioned heuristic; placement-specific physiological or motion models are not claimed.
