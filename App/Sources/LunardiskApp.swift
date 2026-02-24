import SwiftUI

@main
struct LunardiskApp: App {
  @StateObject private var onboardingState: OnboardingStateStore

  init() {
    let resetScopes = PersistedStateScope.resolveFromProcessInfo()
    PersistedState.reset(scopes: resetScopes)
    _onboardingState = StateObject(wrappedValue: OnboardingStateStore())
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(onboardingState)
        .preferredColorScheme(.dark)
    }
    .defaultSize(width: 1120, height: 780)
#if DEBUG
    .commands {
      CommandMenu("Developer") {
        Button("Reset Onboarding State") {
          onboardingState.resetOnboarding()
        }

        Button("Reset All Local State") {
          PersistedState.resetAll()
          onboardingState.reload()
        }
      }
    }
#endif
  }
}
