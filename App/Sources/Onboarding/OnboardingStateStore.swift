import Foundation

@MainActor
final class OnboardingStateStore: ObservableObject {
  @Published private(set) var hasCompletedOnboarding: Bool

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    hasCompletedOnboarding = userDefaults.bool(forKey: PersistedState.onboardingCompletionKey)
  }

  func completeOnboarding() {
    setOnboardingCompleted(true)
  }

  func resetOnboarding() {
    setOnboardingCompleted(false)
  }

  func reload() {
    hasCompletedOnboarding = userDefaults.bool(forKey: PersistedState.onboardingCompletionKey)
  }

  private func setOnboardingCompleted(_ value: Bool) {
    hasCompletedOnboarding = value
    userDefaults.set(value, forKey: PersistedState.onboardingCompletionKey)
  }
}
