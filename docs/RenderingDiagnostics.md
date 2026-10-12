# QuartzCore rendering diagnostic

Reported message: `cannot add handler to 0 from 0 - dropping`, subsystem `com.apple.coreanimation`, library QuartzCore, category API. User observed it while Tempo was running and suspected connection or sync. The message contains no app call stack or affected view.

## Evidence collected on 2026-10-12

- The exact message occurs in Tempo's isolated synthetic simulator mode, with Bluetooth and CloudKit disabled.
- A separate, temporary simulator application reproduced the exact message. Its complete SwiftUI content was:

```swift
import SwiftUI
@main struct RenderProbe: App {
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        Text("Rendering probe").navigationTitle("Probe")
      }
    }
  }
}
```

This app contains no Tempo classes, Bluetooth, CloudKit, timers, custom animations, health observations or remote service. It was compiled for arm64 iOS Simulator, minimum iOS26, SDK27 (verified Mach-O build platform), signed ad hoc and launched with simctl. Its scene manifest used the native SwiftUI application configuration. The NavigationStack probe emitted two matching messages at startup; a separate TabView/NavigationStack probe emitted four. These are examples, not a guaranteed frequency.

Probe artifacts remained outside the repository in `/private/tmp/tempo-render-probe`; the temporary app was uninstalled after investigation. Logs: `navigation-quartz.log` and `tabs-quartz.log`. Tempo's original isolated-mode capture: `/private/tmp/tempo-today-quartz-baseline.log`. Query used:

```sh
xcrun simctl spawn SIMULATOR_ID log show --last 2m --style compact \
  --predicate 'process == "RenderProbe" AND subsystem == "com.apple.coreanimation"'
```

## Conclusion and boundary

The rendering diagnostic does not require a band connection or cloud synchronization and can arise in native SwiftUI navigation independent of Tempo's transport/storage logic. This isolates the framework boundary; it does not identify Apple's internal handler or prove that every occurrence is harmless. Simulator flows remained responsive and no crash was observed in the tested navigation/refresh paths.

No log suppression, private API, compatibility-mode appearance change or speculative animation workaround is applied. Physical iPhone reproduction with its exact OS version, especially if accompanied by a freeze/flicker/crash, remains open as D01. Record the screen/action, preceding/following errors and any crash report; test launching without the Xcode debugger. Do not share health payloads or personal account identifiers in public diagnostics.

Community reports on [Apple Developer Forums](https://developer.apple.com/forums/thread/719267) describe related handler diagnostics during native UI interactions. An [iOS27 keyboard report](https://developer.apple.com/forums/thread/841594) includes the exact message but was attributed by its author to Xcode Device Hub keyboard forwarding; that is not established as Tempo's cause. These reports provide context, not an official fix or diagnosis for this installation.

## PointerUI service-port message — 2026-10-12

The exact `non-launching port is incompatible with service identifier "com.apple.PointerUI.pointeruid.default-service"` message also appears in the independent NavigationStack probe (`RenderProbe`, nativeBoardServices XPCErrors). Recorded at startup in both the TabView and NavigationStack probes; filtered evidence is `/private/tmp/tempo-pointer-baseline.log`. Those apps contain no Bluetooth, CloudKit or Tempo code. This establishes a system UI/input-service reproduction, not a fix or proof every occurrence is harmless. No private pointer-service API or entitlement workaround was added. The user's physical OS and any actual input/freeze/crash symptom still need confirmation.
