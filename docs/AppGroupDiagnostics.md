# App Group preferences diagnostic — 2026-10-12

The reported CFPrefs message names `group.app.tempo.personal` and `kCFPreferencesAnyUser`/SystemContainers. Tempo uses public `UserDefaults(suiteName:)`; it does not call private CFPreferences functions, request AnyUser/ByHost preference scope, reset standard defaults or prepend a team identifier to hide logs.

## Verified locally

- App and widget source entitlements use the same `TEMPO_APP_GROUP` build setting; their Info.plist values agree.
- Local developer-signed iPhone artifacts were inspected without publishing account identifiers, certificates or profile payloads. The configured App Group is present in both app/widget code signatures and provisioning entitlements; signatures verify.
- Unsigned build artifacts cannot establish phone entitlement behavior.
- An isolated two-app simulator canary had accessible group containers but did not establish successful cross-process preference delivery. It used ad-hoc signing without the actual phone provisioning context; this is an inconclusive runtime check, not proof that the owner's signed widget fails or succeeds. The diagnostic group and canary were separate from the user's normal data; the temporary apps were removed. Artifacts: `/private/tmp/tempo-prefs-probe/canary.log`.

An [Apple Systems Engineer explanation](https://developer.apple.com/forums/thread/51348) identifies this historical message as a spurious diagnostic that could also catch normal public API usage. That is relevant context, not a blanket guarantee for the current OS or a substitute for testing widget updates.

## Actual next check

On the signed phone, turn demo off, add the Tempo widget, and check that the widget timestamp/readiness/sleep summary updates after opening Tempo. Compare behavior after relaunch. If sharing fails, inspect the installed app/extension signatures and profiles plus relevant sandbox/cfprefsd errors. Do not rename the group or delete the app/history solely to silence this message. Preserve the original shared namespace and backups.

Local collection uses SQLite in Tempo's app container; this shared-defaults domain carries only widget summary/privacy fields and is separate from band collection and private CloudKit history.

The widget decoder was corrected so an absent readiness key cannot become score0 through `integer(forKey:)`'s default. Missing/out-of-range values remain unavailable. This guards an actual missing-data case; it does not claim to suppress or resolve the OS diagnostic. Physical widget sharing remains an open validation gate (D02/V01).

## User-reported signed-phone check

On 2026-10-12 the owner confirmed the Home Screen widget timestamp updates after opening Tempo with demo off, while reporting the CFPrefs diagnostic. This is user-reported evidence for that field, not an automated signed-phone test or proof of every widget field/relaunch condition. No timestamp-sharing failure is currently reported; the warning is retained for context rather than suppressed. Remaining widget/privacy/relaunch coverage is V01.
