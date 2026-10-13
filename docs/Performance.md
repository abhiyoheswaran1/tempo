# Performance and collection integrity

This pass optimises the existing native collection and presentation paths. It does not establish physical overnight/background acceptance; D05 and C03 remain separate gates.

## Durable collection and quieter presentation

Every accepted live observation still enters the SQLite actor immediately. FULL synchronous transactions, immutable-observation checks, history raw-frame/checkpoint storage and acknowledgement-after-commit remain unchanged. The new `CommittedMeasurementBuffer` receives only successful commits: it is a presentation cache, never the sole copy of data.

The large observable measurement array is published at the existing15-second summary cadence, after4096 pending committed observations, or when an explicit summary/foreground/database refresh needs it. Immediate live BPM, source selection and collection diagnostics retain their small current-reading state. Retained presentation records cover two days; SQLite retains older history. No readings are discarded from storage to meet a UI budget.

Chronological live observations append without rescanning the full retained window per packet. Late history is deduplicated by stable observation ID and sorted. Same-dataset database refresh merges receipts committed while the read was in flight and applies known tombstones. Tombstones remain effective during history replay. Dataset switching drains pending writes and clears presentation again before assigning another store, preventing real/demo mixing.

## Timeline and summary calculation

Canonical reconciliation retains one winner index per numeric metric/time bucket. Source override, active source, wear evidence, physiological eligibility and origin retain their ranking. A chronological result avoids a redundant final sort; late input or winner replacement triggers sorting. Equal instants have stable ID ordering. Reference-parity tests cover mixed sources, quality flags, overrides and multiple bin sizes.

Readiness and daily cardiovascular load share one canonical projection. The immutable `PresentedHealthSummary` runs in a detached utility task outside the UI actor. Publication checks cancellation, calculation generation and store identity. The widget consumes the already-calculated readiness snapshot instead of recomputing it. Algorithms and physiological input requirements are unchanged; unavailable current summaries remain unavailable.

## Widgets and task ownership

The containing app requests widget publication immediately when the displayed score, saved sleep duration or privacy choice changes, and on an explicit foreground refresh. Unchanged content is coalesced to30 minutes. WidgetKit still controls actual delivery; this policy is not a background-execution guarantee. See [Apple's widget refresh guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/).

Delayed summary work checks its expected store after suspension points. An owner token prevents a canceled older task from clearing a replacement task. Dataset transitions cancel prior scheduled work and invalidate summary generation.

## Reproducible software measurement

Run the core suite with the Xcode toolchain. The benchmark is opt-in, avoiding timing assertions on heterogeneous CI machines:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEMPO_BENCHMARK=1 swift test -c release --filter PerformanceTests
```

The fixture contains86,400 unique, chronologically ordered observations. Five reconciliation passes compare the retained original test-only implementation with the current implementation in the same process. On the development Mac, the final run measured2.059 seconds versus0.085 seconds, approximately24 times faster for that common path. These are elapsed desktop fixture timings, not physical iPhone CPU, battery or frame-rate measurements. Unordered/multiple-source workloads have separate correctness coverage and may require sorting.

The raw receipt-array benchmark measured0.073 seconds for300 old pruning operations versus0.130 seconds for the new buffered path with20 publications. The buffer adds maintenance overhead in that isolated microbenchmark; its benefit is reducing large observable publications from300 to20 and moving expensive summary calculation away from the UI actor. It is not evidence of lower total receipt CPU by itself.

Both physical Time Profiler attachment attempts failed to locate Tempo, despite the device process inventory listing it. No physical before/after CPU reduction is claimed. Recheck sustained foreground collection, chart scrolling, lock/background recovery and overnight operation on the signed build; retain any resource-termination log under D05. Private traces and health payloads are not committed.
