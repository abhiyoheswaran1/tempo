# Tempo working conventions

- Open Tempo.xcworkspace (or Tempo.xcodeproj), scheme Tempo, for the iPhone app. Package.swift/TempoCore is the non-executable core library.
- Read the relevant open items in docs/Improvements.md before work. Assign a stable ID to a new material finding and record priority, acceptance checks and whether it needs physical hardware.
- Keep the active tracker short. After acceptance checks pass, remove the closed ticket and append one compact outcome/commit/verification entry to docs/Completed.md. Never close a physical-validation gate using simulator/parser/build evidence.
- Keep durable contracts, methodology and limitations in their technical documents; Git retains investigation detail and superseded plans. docs/Verification.md contains the latest reproducible evidence, not an ever-growing transcript.
- UI changes require fresh real simulator captures for README/gallery when screenshots become outdated. Keep synthetic data visibly labelled and isolated, and record capture provenance/checksums. Do not publish personal device/account screenshots or real health records.
- Preserve immutable observations, correction ancestry, account isolation and unsupported/missing states. Do not infer wearing placement or on-body status from proximity. Do not fabricate physiological values or protocol success.
