# Day history and daily observations

Tempo's day explorer, daily sleep comparison and sleep rhythm are read-only projections over original measurements and saved session/journal revisions. They need no internet, cloud service or LLM. They do not change collection, historical transfer, readiness or load algorithms.

## Your days

Tap the date beside Tempo on Today. Use the native date picker or previous/next-day controls. A day is the half-open local interval `[calendar start of day, next calendar start)`, including 23- and 25-hour daylight-saving days. Measurement instants remain UTC. Sleep belongs to its wake date; naps remain separate. Session reconciliation happens before date filtering, so an edit crossing midnight cannot resurrect the original on the former wake day.

The selected date is queried from SQLite, rather than Today's two-day in-memory measurement cache. HR queries cap at100,000 observations; other supported daily metrics cap at2,000. Cap-hit results are labelled potentially incomplete. Coverage and covered-time average preserve gaps longer than ten seconds. Imported HR is permitted only in this historical reader; it does not become live Bluetooth evidence. Load still uses reconciled, quality-eligible HR. Other metric summaries disclose their daily method and origins; HRV values may come from differing contexts and are not automatically overnight values.

Async results are accepted only for the same date, store, demo mode and request token. Rapid date changes cancel and debounce obsolete work. The page refreshes on opening, app activation, pull-to-refresh and coalesced committed-history updates while visible; its loaded timestamp makes snapshot freshness explicit. Pending refresh work is cancelled on date/dataset changes, disappearance or scene inactivity. It does not run a per-second chart query.

Past-day journal creation uses the selected date. Time-only caffeine edits anchor to the journal's recorded local date/timezone. Empty answers remain unknown. Manual sleep recording from a historical day starts the editor on that date; saving uses the existing versioned correction path. Existing observations are retained.

## What stands out

Version: `daily-observation-1.0`.

This initial rule compares today's primary saved sleep duration with the median of prior primary sleeps ending in the preceding28 calendar days. A comparison requires today's saved session and at least seven distinct prior wake dates. Each date contributes one primary session (the longest reconciled non-nap saved session, with stable identity tie-breaking). Today's value is excluded from its own reference.

A difference of at least30 minutes yields a shorter/longer-duration statement; smaller differences are described as close to usual. Headline differences round to15 minutes. The detail shows current duration, reference median, sample size, contributing session IDs through session links, and algorithm version. If coverage is insufficient, the section explains that comparison is unavailable instead of producing a number.

Naps, future/invalid records, unconfirmed estimates and imported intervals awaiting whole-night reconciliation are excluded. Synthetic records require explicit demo opt-in. Manual timing is information supplied by the user; it is not promoted to a direct sensor measurement. This is descriptive duration context, not a validated recovery assessment, sleep-quality judgement, causal association or medical recommendation. Journal associations and automatic “improved consistency” claims are not part of this rule.

## Sleep rhythm

Fourteen- and28-day views plot one primary saved sleep per wake date. Dates use the viewing phone's calendar; each bar's clock times use the session's recorded timezone. Midnight is the reference, so a bedtime on the preceding date has a negative hour coordinate. Unusual daytime schedules remain representable. Empty dates stay empty. Missing/invalid recorded timezones are not guessed into chartable timings; session evidence remains accessible through Your days.

Bar width represents clock timing, while elapsed duration is computed from UTC instants and can differ across DST. Travel may change clock timing without changing elapsed duration. No stages or sleep-quality score are inferred. The nightly list provides an accessible alternative to the chart and opens timing/source/correction detail.

## Bug pass

Regression tests reproduced and fixed unstable equal-rank overlapping sleep selection and acceptance of infinite session dates. New reader tests also caught correction suppression across midnight and manual nap reclassification. Review caught historical caffeine date anchoring and missing truncation disclosure; both were addressed. Original sessions/measurements, correction ancestry and sync account isolation are preserved.

Software checks are recorded in [Verification](Verification.md). Physical background/CPU, Health permissions and multi-phone cloud acceptance gates remain tracked separately. This feature pass does not assert those hardware gates complete.
