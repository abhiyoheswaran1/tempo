import SwiftUI

@main struct TempoApp: App {
  @State private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      RootView().environment(model).modifier(TestAppearance()).task {
        await model.start()
        if ProcessInfo.processInfo.arguments.contains("--demo") {
          await model.setDemo(true)
          if ProcessInfo.processInfo.arguments.contains("--activity-detection-demo") {
            model.mutate { try await model.setAutomaticDetectionEnabled(true) }
          }
        }
      }
    }
  }
}

private struct TestAppearance: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if ProcessInfo.processInfo.arguments.contains("--ui-testing")
      && ProcessInfo.processInfo.arguments.contains("--large-text")
    {
      content.environment(\.dynamicTypeSize, .accessibility5).preferredColorScheme(
        ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
    } else {
      content
    }
  }
}
