import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct LunardiskApp: App {
  @StateObject private var onboardingState: OnboardingStateStore

  init() {
#if os(macOS)
    if let appIcon = NSImage(named: NSImage.Name("AppIcon")) {
      NSApplication.shared.applicationIconImage = appIcon
    }
#endif
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
    .defaultSize(width: 1120, height: 720)
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
