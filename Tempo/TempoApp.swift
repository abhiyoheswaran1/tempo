import SwiftUI

@main struct TempoApp: App {
  @State private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      RootView().environment(model).task {
        await model.start()
        if ProcessInfo.processInfo.arguments.contains("--demo") { await model.setDemo(true) }
      }
    }
  }
}
