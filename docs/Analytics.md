# Tempo analytics 1.0

These are original transparent personal-guidance estimates, not Whoop's recovery algorithm or medical validation.

## Immutable inputs

Measured HRS HR/RR; imported Health HR/RHR/SDNN/sleep; manual sleep/journal/workouts. RMSSD is never synthesized from an HR series. No inferred SpO2, temperature, respiratory rate, calorie expenditure or detailed sleep staging. Manual session edits use revision ancestry and survive reanalysis; concurrent heads need user resolution.

UTC instants drive elapsed durations. Sessions retain an IANA timezone for local presentation; DST does not change elapsed sleep/workout seconds. Canonical one-second bins choose valid source records using temporary override, latest active-source transition, contact status and direct-measurement priority. RR timing within a packet is not independently timestamped. Source observations remain stored.

## RR preprocessing

Intervals must be finite and300–2000ms. A successive change above20% is rejected. Rejection breaks adjacency so RMSSD does not bridge an artefact. At least240 accepted intervals and90% acceptance, with sufficient adjacent pairs, are needed by default. RMSSD is sqrt(mean successive squared differences); SDNN uses sample standard deviation of accepted normal intervals. These heuristics are conservative, not an ECG artefact validation study.

Overnight analysis requires one contiguous last-five-minute window: at least240 one-second canonical samples, no gap above2s and qualifying RR. This window is a limited overnight estimate, not a whole-night median HRV. Breathing-session HRV must never enter nightly baselines.

Resting HR is an overnight10th-percentile estimate requiring70% one-second coverage. Sleep duration is manually entered or imported; automatic detection/staging is unavailable because no defensible motion input is enabled. Overlapping sessions are projected with manual priority rather than summed. Imported stages are preserved as raw sessions; current projection is conservative and does not invent a hypnogram.

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
