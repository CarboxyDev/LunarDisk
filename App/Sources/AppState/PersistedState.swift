import Foundation

enum PersistedStateScope: String, CaseIterable, Hashable {
  case onboarding
  case all

  static func parse(tokens: [String]) -> Set<PersistedStateScope> {
    Set(tokens
      .flatMap { $0.split(separator: ",") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .compactMap(Self.init(rawValue:)))
  }

  static func resolveFromProcessInfo(_ processInfo: ProcessInfo = .processInfo) -> Set<PersistedStateScope> {
    var tokens: [String] = []

    for argument in processInfo.arguments {
      if argument == "--reset-state-all" {
        tokens.append(PersistedStateScope.all.rawValue)
      } else if argument.hasPrefix("--reset-state=") {
        tokens.append(String(argument.dropFirst("--reset-state=".count)))
      }
    }

    if let resetState = processInfo.environment["LUNARDISK_RESET_STATE"], !resetState.isEmpty {
      tokens.append(resetState)
    }

    return parse(tokens: tokens)
  }
}

enum PersistedState {
  static let onboardingCompletionKey = "hasCompletedOnboarding"
  static let fullDiskScanDisclosureAcknowledgedKey = "hasAcknowledgedDiskScanDisclosure"

  static func reset(scopes: Set<PersistedStateScope>, userDefaults: UserDefaults = .standard) {
    guard !scopes.isEmpty else { return }

    if scopes.contains(.all) {
      resetAll(userDefaults: userDefaults)
      return
    }

    if scopes.contains(.onboarding) {
      userDefaults.removeObject(forKey: onboardingCompletionKey)
    }
  }

  static func resetAll(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: onboardingCompletionKey)
    userDefaults.removeObject(forKey: fullDiskScanDisclosureAcknowledgedKey)
  }
}
