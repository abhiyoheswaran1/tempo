# Tempo implementation plan

Goal: a local-first personal iPhone companion for two owned Whoop bands, with an original native implementation and auditable measurements.

Architecture: platform-independent Swift core for protocol, reconciliation, analytics and SQLite persistence; iOS adapters for Core Bluetooth, CloudKit and HealthKit; SwiftUI navigation and WidgetKit/ActivityKit extension. Immutable observations and correction events retain provenance. No dependencies or backend.

1. Protocol and feasibility: research UUIDs, framing, sensor contracts and firmware boundaries; write malformed-packet tests before parsers. Standard HR is the initial live path for both families. No destructive, authentication, update or firmware commands.
2. Integrity core: SQLite WAL transactions; stable IDs; bounded batches; history cursor commit ordering; immutable edits, tombstones and durable outbox. Test duplicates, overlaps, restore and failed writes.
3. Collection and analytics: explicit hysteresis selection; persistent workout transitions and source segments; RR quality, RMSSD/SDNN, load, conservative readiness and association minimums. Test missing inputs, sparse history and timezone handling.
4. Native shell: Today, Activity, Trends, registry/reconnection, journal, sleep corrections, backup and collection health; genuine Bluetooth notification collection. Synthetic demo uses a separate database and cannot sync or export to Health.
5. Continuity: private zone, incremental change tokens, encrypted bounded payloads, immutable conflict policy, retry, deletion events and account isolation; optional granular HealthKit with stable export identifiers and source exclusion.
6. Extensions and verification: widgets, workout Live Activity, accessibility and setup docs. Build simulator/device without signing; run core tests. Physical validation and provisioning remain distinct.

Execution: inline in the supplied empty workspace, as requested. User specification overrides intermediate approval gates. No release/merge/push. Signing identifiers are configurable; no credentials needed to build unsigned.

Review focus: unknown firmware never inherits proprietary layouts; stale HR never proves wear; cloud account change never uploads old history; duplicate imports remain idempotent; a paused/relaunched workout does not gain false coverage.

## Execution ledger

Completed: native project/app/extensions/UI test target; constructed protocol parser tests; local transactional store and immutable revisions; source/workout/session projection; core analytics; genuine standard HRS transport; optional CloudKit and HealthKit adapters; SwiftUI screens; backup and setup/research/validation documentation. Final33 core tests and2 simulator UI tests pass; unsigned iPhone build passes.

Rulings: use the supplied empty workspace inline per user instruction; no approval-only planning stop. Use iOS26 deployment with verified installed Xcode27 tooling. Do not send history acknowledgements that permit reclamation under the user's destructive-command prohibition. Keep deeper unsupported physiological/haptic features unavailable. Account-namespaced zone and immutable correction heads preserve ownership and edit history.

Physical gates and unimplemented product work are enumerated in KnownLimitations.md. This ledger does not mark the whole daily-use specification achieved.
