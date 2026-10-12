# Collection, Today, Trends and Live refinement

Goal: understand what Tempo knows now, find useful data while a baseline builds, and inspect history without technical clutter. Native SwiftUI, iOS26 minimum, existing design and isolated demo remain unchanged.

1. Collection: one status derived from a valid measured HR timestamp and actual connection; contact evidence separate. Band-status sheet exposes explicit HR receipt, unavailable historical retrieval, independent iCloud status and per-band connection actions. Nearby never means connected or worn.
2. Today: when no justified score exists, replace the large dash with compact baseline progress and show collection first. Preserve sleep, activity, journal and explanation. Available readiness retains its presentation.
3. Trends: one selected metric (including sleep); day selection requires that local day to exist, so gaps cannot silently select a neighbour. Keep range, units, source, origin, coverage and algorithm accessible. Sleep uses stored reconciled sessions and preserves manual provenance; naps excluded as before.
4. Live: dominant valid current/recent HR, exact received time, stale value in a separate last-reading state; gap-preserving five-minute chart. Compact statistics, source/wear and optional R-R evidence progressively disclosed. No invented additional sensors.

Software verification sequence: record six recommendations (UX12–16 plus existing UX09); baseline core suite; red/green presentation and selection tests; integrate collection/Today; integrate Live/Trends; simulator interaction/accessibility tests and unmodified captures; unsigned phone build; read-only review; close only software tickets and update README/verification. Workout detail (UX09) and fast journal (UX16) are recorded, not part of this pass.

Physical gates C01/C03/C04/S01/V01/V05 remain open. No new protocol commands, historical transfer, cloud scheduling or medical analytics are introduced by this UI pass.

Recorded recommendations: 1 collection UX12, 2 Today UX13, 3 workout detail UX09, 4 fast journal UX16, 5 Trends UX14, 6 Live UX15. Completed outcomes move to Completed.md; unresolved items remain in Improvements.md. Source metadata for removed registrations remains named as archived in Trends; Live requires a current registered source.

## Today redesign and render cost

Today uses a native large navigation title, one rule-based headline, compact justified readiness, a prominent live-reading entry and paired sleep/movement summaries. Accessibility sizes stack summaries vertically. Refresh and separate collection/iCloud timestamps stay together; journal is a simple footer entry. Content remains opaque, with native navigation glass. Missing and stale readings retain explicit states.

A per-device latest-valid-HR index replaces full history scans on every live render. Readiness and daily load refresh after load, foregrounding and the existing coalesced snapshot; the readiness cache also checks the currently eligible sleep, so its 36-hour limit cannot be hidden by caching. A visible minute timeline refreshes date/expiry; it does not promise background execution. The optional reported battery header expires after one hour and exposes its value to VoiceOver.
