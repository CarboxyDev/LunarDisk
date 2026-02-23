import Foundation
import XCTest
@testable import Lunardisk

@MainActor
final class LunardiskTests: XCTestCase {
  func testInitialModelState() {
    let model = AppModel()

    XCTAssertNil(model.selectedURL)
    XCTAssertNil(model.rootNode)
    XCTAssertTrue(model.insights.isEmpty)
    XCTAssertFalse(model.isScanning)
    XCTAssertNil(model.errorMessage)
  }

  func testOnboardingStateStorePersistsCompletionAndReset() {
    let userDefaults = makeIsolatedDefaults()
    defer { clear(userDefaults) }

    let store = OnboardingStateStore(userDefaults: userDefaults)
    XCTAssertFalse(store.hasCompletedOnboarding)

    store.completeOnboarding()
    XCTAssertTrue(store.hasCompletedOnboarding)
    XCTAssertTrue(userDefaults.bool(forKey: PersistedState.onboardingCompletionKey))

    store.resetOnboarding()
    XCTAssertFalse(store.hasCompletedOnboarding)
    XCTAssertFalse(userDefaults.bool(forKey: PersistedState.onboardingCompletionKey))
  }

  func testPersistedStateScopeParsingAndReset() {
    let userDefaults = makeIsolatedDefaults()
    defer { clear(userDefaults) }

    userDefaults.set(true, forKey: PersistedState.onboardingCompletionKey)
    let scopes = PersistedStateScope.parse(tokens: [" onboarding,all "])
    XCTAssertTrue(scopes.contains(.onboarding))
    XCTAssertTrue(scopes.contains(.all))

    PersistedState.reset(scopes: [.onboarding], userDefaults: userDefaults)
    XCTAssertFalse(userDefaults.bool(forKey: PersistedState.onboardingCompletionKey))
  }

  private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "com.lunardisk.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      fatalError("Failed to create isolated UserDefaults suite")
    }
    clear(defaults)
    return defaults
  }

  private func clear(_ userDefaults: UserDefaults) {
    userDefaults.removeObject(forKey: PersistedState.onboardingCompletionKey)
  }
}
