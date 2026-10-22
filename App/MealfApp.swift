import SwiftUI

@main struct MealfApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("biometricLock") private var biometricLock = false
  var body: some Scene {
    WindowGroup {
      RootView().environment(model).onOpenURL { model.openDestination($0) }.task {
        await model.start()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background && biometricLock { model.locked = true }
        if phase == .active {
          Task {
            Task { await model.retrySignOuts() }
            if model.locked { await model.unlock() }
            if !model.locked { await model.synchronise() }
          }
        }
      }
    }
  }
}
