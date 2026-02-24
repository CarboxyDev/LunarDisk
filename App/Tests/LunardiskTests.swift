import Foundation
import XCTest
import CoreScan
import LunardiskAI
@testable import Lunardisk

@MainActor
final class LunardiskTests: XCTestCase {
  actor ControlledScanner: FileScanning {
    private var continuations: [CheckedContinuation<FileNode, Error>] = []

    func scan(at url: URL, maxDepth: Int?) async throws -> FileNode {
      try await withCheckedThrowingContinuation { continuation in
        continuations.append(continuation)
      }
    }

    func pendingCount() -> Int {
      continuations.count
    }

    func succeedNext(with node: FileNode) {
      guard !continuations.isEmpty else { return }
      let continuation = continuations.removeFirst()
      continuation.resume(returning: node)
    }
  }

  actor ControlledAnalyzer: AIAnalyzing {
    private let output: [Insight]

    init(output: [Insight]) {
      self.output = output
    }

    func generateInsights(for root: FileNode) async -> [Insight] {
      output
    }
  }

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

  func testSelectScanTargetResetsViewState() {
    let model = AppModel()
    model.rootNode = FileNode(name: "tmp", path: "/tmp", isDirectory: true, sizeBytes: 10)
    model.insights = [Insight(severity: .info, message: "sample")]
    model.errorMessage = "error"
    model.lastFailure = .unknown(message: "fail")

    let target = URL(fileURLWithPath: "/Users", isDirectory: true)
    model.selectScanTarget(target)

    XCTAssertEqual(model.selectedURL, target)
    XCTAssertNil(model.rootNode)
    XCTAssertTrue(model.insights.isEmpty)
    XCTAssertNil(model.errorMessage)
    XCTAssertNil(model.lastFailure)
  }

  func testCancelScanIgnoresLateScannerResult() async {
    let scanner = ControlledScanner()
    let analyzer = ControlledAnalyzer(output: [Insight(severity: .info, message: "ok")])
    let model = AppModel(scanner: scanner, analyzer: analyzer)
    let target = URL(fileURLWithPath: "/tmp", isDirectory: true)

    model.selectScanTarget(target)
    model.startScan()

    await waitForPendingScans(scanner, expected: 1)
    model.cancelScan()

    await scanner.succeedNext(with: FileNode(name: "tmp", path: "/tmp", isDirectory: true, sizeBytes: 42))
    await Task.yield()

    XCTAssertFalse(model.isScanning)
    XCTAssertNil(model.rootNode)
    XCTAssertTrue(model.insights.isEmpty)
  }

  func testOlderScanCannotOverrideNewerScan() async {
    let scanner = ControlledScanner()
    let analyzer = ControlledAnalyzer(output: [Insight(severity: .info, message: "ok")])
    let model = AppModel(scanner: scanner, analyzer: analyzer)

    model.selectScanTarget(URL(fileURLWithPath: "/tmp/old", isDirectory: true))
    model.startScan()
    await waitForPendingScans(scanner, expected: 1)

    model.selectScanTarget(URL(fileURLWithPath: "/tmp/new", isDirectory: true))
    model.startScan()
    await waitForPendingScans(scanner, expected: 2)

    await scanner.succeedNext(with: FileNode(name: "old", path: "/tmp/old", isDirectory: true, sizeBytes: 1))
    await Task.yield()
    XCTAssertNil(model.rootNode)

    await scanner.succeedNext(with: FileNode(name: "new", path: "/tmp/new", isDirectory: true, sizeBytes: 2))
    await waitForRootNode(model, expectedPath: "/tmp/new")

    XCTAssertEqual(model.rootNode?.path, "/tmp/new")
    XCTAssertEqual(model.rootNode?.sizeBytes, 2)
  }

  private func waitForPendingScans(_ scanner: ControlledScanner, expected: Int) async {
    for _ in 0..<60 {
      if await scanner.pendingCount() >= expected {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for pending scans: expected \(expected)")
  }

  private func waitForRootNode(_ model: AppModel, expectedPath: String) async {
    for _ in 0..<60 {
      if model.rootNode?.path == expectedPath {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for rootNode at \(expectedPath)")
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
