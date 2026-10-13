# Tempo analytics methodology

These are original transparent personal-guidance estimates, not Whoop's recovery algorithm or medical validation.

## Immutable inputs

Measured HRS HR/RR; imported Health HR/RHR/SDNN/sleep; manual sleep/journal/workouts. RMSSD is never synthesized from an HR series. No inferred SpO2, temperature, respiratory rate, calorie expenditure or detailed sleep staging. Manual session edits use revision ancestry and survive reanalysis; concurrent heads need user resolution.

UTC instants drive elapsed durations. Sessions retain an IANA timezone for local presentation; DST does not change elapsed sleep/workout seconds. Canonical one-second bins choose valid source records using temporary override, latest active-source transition, contact status and direct-measurement priority. RR timing within a packet is not independently timestamped. Source observations remain stored.

Overnight cache version3 includes source-segment contents as well as observation/deletion coverage. Source corrections invalidate prior overnight results even when the number of segments is unchanged. Observations remain immutable.

## RR preprocessing

Intervals must be finite and300–2000ms. A successive change above20% is rejected. Rejection breaks adjacency so RMSSD does not bridge an artefact. At least240 accepted intervals and90% acceptance, with sufficient adjacent pairs, are needed by default. RMSSD is sqrt(mean successive squared differences); SDNN uses sample standard deviation of accepted normal intervals. These heuristics are conservative, not an ECG artefact validation study.

Overnight analysis requires one contiguous last-five-minute window: at least240 one-second canonical samples in a single RR-bearing source run, no gap above2s and qualifying RR. Missing RR packets and source changes break adjacency; runs cannot be joined to reach minimum coverage. This window is a limited overnight estimate, not a whole-night median HRV. Breathing-session HRV must never enter nightly baselines.

Resting HR is an overnight10th-percentile estimate requiring70% one-second coverage. Sleep duration is entered/imported or explicitly confirmed from experimental sustained-rest proposals. HR-only candidates are not established sleep and do not contribute to readiness until confirmed; motion-backed detection and staging remain unavailable. Overlapping sessions are projected with manual priority rather than summed. Imported stages are preserved as raw sessions; current projection is conservative and does not invent a hypnogram.

## Baseline/readiness

Prior28 qualifying nights; minimum7 nights yields provisional status and21 establishes confidence. Log RMSSD, RHR and sleep-hours inputs use median and1.4826*MAD, with floors0.1 log units,3bpm and0.5h. Contributions clamp to±2; RHR direction is inverted. At least2 available inputs. Score=60+15*mean(contributions), rounded to5. Missing inputs are omitted, never zero. Confidence combines available-input fraction and baseline-night count. This version does not incorporate subjective fields, respiratory rate or recent load into readiness.

Changing bands preserves history but device offsets are not calibrated. The explanation states that limitation. A source change within28days halves readiness confidence; history is preserved. Device-conditioned offset estimation remains unavailable, so scores are not fully comparable across bands.

## Cardiovascular load

Edwards zone minutes:50–60,60–70,70–80,80–90 and≥90% of user-configured maximum HR carry weights1–5. Samples below50% accrue zero zone points but retain measured coverage. Maximum HR default190 is an editable assumption. Integration covers only consecutive samples≤10s apart; pauses/disconnections are excluded. No interpolation across gaps. Heart rate does not quantify muscular load; strength sessions can retain perceived exertion and notes.

## Associations

Pearson correlation requires≥30 finite paired observations and nonzero variance. Fisher-z95% interval communicates uncertainty. Missing/unanswered journal values are excluded. The present UI suppresses insights until an eligible analysis is connected; no fabricated patterns. Confounding and self-selection remain; correlations do not establish causation.

Algorithm identifiers: readiness-1.0; night-v1 cache; backup tempo-1.0. Cached nightly inputs are local projections rebuilt from retained observations and sleep corrections. Export includes schema and algorithm version, observation origin/quality/source/transport/RR and revision ancestry.

## Experimental activity suggestions

The original heart-rate-only candidate model is documented in [AutomaticActivity.md](AutomaticActivity.md). It identifies sustained elevation, requires explicit user confirmation, and does not classify sports. Confirmed workouts retain estimated provenance and algorithm version; no medical or WHOOP-equivalence claim is made.

## Placement context in readiness v1.1

Reported wrist/upper-arm/underwear changes within available measured overnight samples multiply confidence by0.75, a conservative product heuristic without validation as a probability of accuracy. The readiness score, input values and retained baseline are unchanged. Current comparison uses the two-day in-memory sample window and cannot audit all28 baseline days. No placement-specific sensor correction is claimed. Unknown/conflicted contexts remain unknown. See [WearingPlacement.md](WearingPlacement.md).

## Presentation and daily summaries

Today uses qualitative evidence categories instead of displaying heuristic confidence as a percentage: building at zero/unavailable, limited below0.5, developing below0.8, strong otherwise. These are product categories, not calibrated probabilities. Numeric readiness and RMSSD/SDNN formulas are retained. Current readiness requires a non-nap qualifying sleep lasting at least4h and ending within36h; older inputs stay in history/baselines but cannot supply today's score. Sleep details show the source date; naps are excluded from the main overnight summary.

Daily-summary v1.0 groups instants by the current display timezone using calendar day boundaries, including23/25h DST days. Heart rate is the time-weighted mean only across accepted adjacent samples at most10s apart, clipped at midnight. At least60s covered exposure is required. This is not an all-day or resting HR estimate; partial coverage is visible. Canonical source selection removes overlapping band exposure. Summary evidence/digest includes contributing midnight-boundary records. Resting HR/RMSSD/SDNN use daily medians of available inputs; short/overnight contexts may differ, so these charts are not automatically overnight baselines. Weight uses the latest daily measurement. Units, sample count, input origins, sources and algorithm version remain inspectable. Missing days split chart lines; the observed daily range is descriptive, not a normal/healthy reference range.

Queries are bounded per day to200,000 records, with explicit truncated-summary labeling. Deletions are excluded, and per-day cancellation/yields allow pending collection work between days. Large-volume caching/compaction remains S03. History loads invalidate charts regardless of the recent two-day sample count; live refresh is coalesced to five-minute bins and manual refresh is available.

The refined Trends screen shows one selected metric, including a separate sleep-session view. Measurements are plotted at local noon for their summary day so tapping a point does not accidentally select the preceding day at midnight. Selection resolves only within that local calendar day, including DST transitions; an empty day never borrows a neighbour's value. Daily rows provide an alternative to touching chart points. The selected value's evidence discloses origin, sources, coverage/truncation and algorithm version. Sleep bars remain individual reconciled non-nap sessions by end date; selecting a day lists its sessions and their detail/edit entry, without a new sleep-detection or staging claim.

When readiness has no score, Today shows compact baseline progress and brings collection first. The calculation and minimum coverage remain unchanged; unavailable scores no longer occupy a large numeric placeholder. Established available scores retain their evidence entry. Trends preserve the existing five-minute incoming-data refresh window, with request/dataset guards preventing obsolete asynchronous results from replacing current history.

Removed registrations retain their available friendly name as archived source evidence. Missing registry metadata is labelled unresolved, not assumed to be imported.

Cardiovascular load clips each accepted adjacent interval at workout bounds and subtracts the union of pause intervals, including an ongoing pause. Paused samples remain interval boundaries so filtering them cannot bridge a pause or data gap. Original intervals above10s remain excluded.

## Experimental historical quality

WHOOP5 R18 primary HR remains inspectable as a direct experimental reading. Opaque cardiac/quality flags are preserved in optional `qualityContext`; unknown flags are not treated as validated physiological signal quality. Such records cannot provide resting HR, overnight HRV, cardiovascular load, automatic workout suggestions or Health exports. Raw RR words are retained for future validation, not consumed by RMSSD. Readiness version1.2 and night-input cache3 disclose this stricter input qualification.

Live chart coverage and its time-weighted mean are descriptive receipt statistics across canonical adjacent readings at most10s apart. They may include experimental primary HR, with an explicit explanation. They are separate from training-load eligibility. Canonical overlap selection prefers a qualified reading below explicit source override/active-source/wear priorities; observations remain immutable. No source-quality probability or validation claim is implied.

## Experimental possible-sleep detector1.0

Runs locally after history commits and on dataset load over the last48hours. Canonical finite HR30–220, excluding recorded workouts and off-body/invalid observations, is reduced to one sample per UTC second. At least4hours of readings and a10bpm difference between20th/90th percentiles are required. Five-minute bins need80% coverage and no gap over30seconds; median HR must be at most min(80,20th percentile+5)bpm. At least24 consecutive bins (2hours),30minutes since the end and a higher HR reading within an hour of the end are required. Missing bins split runs; naps under2hours are not detected. Bin timing is approximate, not physiological sleep/wake measurement.

Possible sleep is explicitly HR-only and experimental: quiet wakefulness, medication and charging artifacts with unknown contact may resemble rest. Unresolved W5 quality flags can participate in these descriptive proposals, but are still excluded from RHR/HRV/readiness/load. Candidates do not enter sleep totals, Health or readiness until the user reviews timing and saves a manual confirmation. Detailed stages are absent. Existing sleep revisions, corrections and dismissals suppress overlapping proposals. Confirmed sleep retains algorithm version, input count/digest and original coverage; the digest refers to immutable observation IDs in the retained UTC window. Automatic inference does not overwrite edits. Manual confirmation supplies sleep duration; unsupported overnight metrics remain missing. Timezone at detection is recorded; historical travel timezone cannot be inferred from HR.

### Trends period overview

“Typical recorded day” is the median of the selected metric's recorded daily summaries, with each day weighted equally. It is a descriptive summary, not a recovery assessment. Missing days are excluded rather than treated as zero; the page shows recorded-day count, fraction and daily-value range. This fraction describes days with qualifying data, not continuous sensor coverage. Any truncated daily summary makes the period visibly incomplete. HR remains a covered-time daily average, with its partial-day caveat and per-day coverage available below the chart. No previous-period health judgement is inferred from uneven recording.

The page retains its chart and selected day during refreshes of the same metric, range, store and demo mode. Switching those identities clears the old values; request guards continue to reject obsolete results. Journal associations are explicitly unavailable rather than presented as an unfinished insight teaser.

### Sleep detail presentation

Sleep detail reads the latest saved revision for the session ID. The duration/timing summary uses the recorded timezone; elapsed duration is independent of daylight-saving changes. A separate bounded HR receipt view retains original readings through the existing canonical timeline and chart reducer. Its covered-time average and contiguous coverage exclude gaps longer than ten seconds; isolated readings remain points even when an average is unavailable. The view queries at most100,000 HR observations and labels limit-hit results incomplete. Descriptive receipt coverage does not qualify unresolved sensor flags for recovery analytics. Recovery inputs continue to use the existing quality-gated methodology.

Timing corrections use the existing revision path; deletion requires confirmation and preserves original observations. This presentation change adds no sleep-stage classification, detection algorithm or physiological estimate.
