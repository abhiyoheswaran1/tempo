# Initial implementation record

The original six phases established the native app/extension project, independent firmware-bounded protocol parsers, transactional immutable storage, source/workout continuity, private CloudKit/Health adapters and transparent analytics. Initial implementation is retained in Git history; it was not a daily-use acceptance sign-off.

Lasting decisions: iOS26 minimum; local database first; one BLE connection until physical validation; ordinary durable receipt ACK only; no forced trim/erase, firmware changes or authentication bypass; unknown measurements remain unavailable; cloud accounts remain isolated; manual edits retain ancestry.

Current work queue: [Improvements.md](Improvements.md). Closed work: [Completed.md](Completed.md). Reproducible evidence: [Verification.md](Verification.md). Product acceptance and physical gates: [KnownLimitations.md](KnownLimitations.md). Architecture/contracts remain in the technical documents.
