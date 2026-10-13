# Collection coverage and overnight reliability

Today’s **Recorded through** link opens a 12- or 24-hour view of locally stored band heart-rate receipts. The latest record is a timestamp, not a claim that every earlier period is complete. Coverage counts intervals between receipts at most 10 seconds apart; overlapping bands do not add duplicate duration. Missing edges and gaps remain visible. The view lists gaps lasting at least a minute, up to 20 at once.

Imported Health records are excluded. Quality-flagged band records can establish receipt availability but are separately identified: receipt coverage does not prove valid physiological coverage, wearing, or sleep. Synthetic records are admitted only in the isolated demo dataset. Queries have a 100,000-record cap; reaching it produces an incomplete-coverage warning. Instants remain UTC and are formatted locally.

## Optional system reports

Recorded coverage → Overnight reliability contains an off-by-default switch. Up to seven system reports stay on this phone in an atomic, file-protected archive bounded to 64KB on read and write. Reports contain period timestamps, app version, CPU time, peak memory and background CPU-limit exits when Apple supplies them. They contain no sensor payloads and are never synced or uploaded. Demo and UI testing disable subscriptions; demo hides existing real reports.

Tempo uses MetricKit APIs supported by its iOS 26 minimum. CPU time represents accumulated processor use across a reporting period, not wall-clock running time or battery percentage. Reports may cover multiple builds and earlier demo usage. Delivery is asynchronous and can take longer than 24 hours; an absent report is not evidence of zero resource use. See Apple’s [metric payload](https://developer.apple.com/documentation/metrickit/mxmetricpayload/) and [cumulative CPU time](https://developer.apple.com/documentation/metrickit/mxcpumetric/cumulativecputime/) documentation. Physical report delivery and overnight resource behaviour still require device validation.

## One-night check

1. Connect your worn band, complete available catch-up and optionally enable local reliability reports.
2. Lock the phone and use it normally. Do not force-quit Tempo; iOS background execution remains system-controlled.
3. In the morning, pull to sync Today, then open Recorded coverage with 12 hours selected. Inspect actual overnight receipts and missing periods before evaluating a sleep proposal.
4. Inspect Overnight reliability once Apple delivers a report, and iPhone Settings → Battery separately. Record the build, period, missing intervals and any system-reported resource-limit exits. Do not share health payloads in public issues.

This procedure distinguishes stored coverage from analytics and resource use. Software tests do not close the overnight physical-validation gates.
