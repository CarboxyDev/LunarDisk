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

  actor ImmediateScanner: FileScanning {
    private let node: FileNode

    init(node: FileNode) {
      self.node = node
    }

    func scan(at url: URL, maxDepth: Int?) async throws -> FileNode {
      node
    }
  }

  actor ImmediateScannerWithDiagnostics: FileScanning {
    private let node: FileNode
    private let diagnostics: ScanDiagnostics?

    init(node: FileNode, diagnostics: ScanDiagnostics?) {
      self.node = node
      self.diagnostics = diagnostics
    }

    func scan(at url: URL, maxDepth: Int?) async throws -> FileNode {
      node
    }

    func lastScanDiagnostics() async -> ScanDiagnostics? {
      diagnostics
    }
  }

  actor StrategyCapturingScanner: FileScanning {
    private let node: FileNode
    private var capturedStrategy: ScanSizeStrategy?
    private var legacyMethodUsed = false

    init(node: FileNode) {
      self.node = node
    }

    func scan(at url: URL, maxDepth: Int?) async throws -> FileNode {
      legacyMethodUsed = true
      return node
    }

    func scan(at url: URL, maxDepth: Int?, sizeStrategy: ScanSizeStrategy) async throws -> FileNode {
      capturedStrategy = sizeStrategy
      return node
    }

    func lastCapturedStrategy() -> ScanSizeStrategy? {
      capturedStrategy
    }

    func didUseLegacyMethod() -> Bool {
      legacyMethodUsed
    }
  }

  actor SlowCancelableAnalyzer: AIAnalyzing {
    private var observedCancellation = false

    func generateInsights(for root: FileNode) async -> [Insight] {
      for _ in 0..<80 {
        if Task.isCancelled {
          observedCancellation = true
          return []
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      return [Insight(severity: .info, message: "done")]
    }

    func cancellationObserved() -> Bool {
      observedCancellation
    }
  }

  func testInitialModelState() {
    let model = AppModel()

    XCTAssertNil(model.selectedURL)
    XCTAssertNil(model.rootNode)
    XCTAssertTrue(model.insights.isEmpty)
    XCTAssertFalse(model.isScanning)
    XCTAssertNil(model.errorMessage)
    XCTAssertNil(model.scanWarningMessage)
    XCTAssertEqual(model.scanSizeStrategy, .allocated)
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

  func testPersistedStateResetAllClearsDisclosureAcknowledgement() {
    let userDefaults = makeIsolatedDefaults()
    defer { clear(userDefaults) }

    userDefaults.set(true, forKey: PersistedState.onboardingCompletionKey)
    userDefaults.set(true, forKey: PersistedState.fullDiskScanDisclosureAcknowledgedKey)

    PersistedState.resetAll(userDefaults: userDefaults)

    XCTAssertFalse(userDefaults.bool(forKey: PersistedState.onboardingCompletionKey))
    XCTAssertFalse(userDefaults.bool(forKey: PersistedState.fullDiskScanDisclosureAcknowledgedKey))
  }

  func testSelectScanTargetResetsViewState() {
    let model = AppModel()
    model.rootNode = FileNode(name: "tmp", path: "/tmp", isDirectory: true, sizeBytes: 10)
    model.insights = [Insight(severity: .info, message: "sample")]
    model.errorMessage = "error"
    model.lastFailure = .unknown(message: "fail")
    model.scanWarningMessage = "partial"

    let target = URL(fileURLWithPath: "/Users", isDirectory: true)
    model.selectScanTarget(target)

    XCTAssertEqual(model.selectedURL, target)
    XCTAssertNil(model.rootNode)
    XCTAssertTrue(model.insights.isEmpty)
    XCTAssertNil(model.errorMessage)
    XCTAssertNil(model.lastFailure)
    XCTAssertNil(model.scanWarningMessage)
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

  func testTopConsumersStoreComputesDirectAndDeepestEntries() async {
    let store = TopConsumersStore()
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 300,
      children: [
        FileNode(
          name: "a",
          path: "/root/a",
          isDirectory: true,
          sizeBytes: 100,
          children: [
            FileNode(name: "a1", path: "/root/a/a1", isDirectory: false, sizeBytes: 90)
          ]
        ),
        FileNode(name: "b", path: "/root/b", isDirectory: false, sizeBytes: 95),
        FileNode(
          name: "c",
          path: "/root/c",
          isDirectory: true,
          sizeBytes: 85,
          children: [
            FileNode(name: "c1", path: "/root/c/c1", isDirectory: false, sizeBytes: 80)
          ]
        )
      ]
    )

    store.prepare(for: root, limit: 2)
    XCTAssertEqual(store.visibleEntries(limit: 2).map(\.node.path), ["/root/a", "/root/b"])

    store.mode = .deepestConsumers
    await waitUntil("deepest entries should be computed") {
      store.entriesByMode[.deepestConsumers] != nil
    }

    XCTAssertEqual(store.visibleEntries(limit: 2).map(\.node.path), ["/root/a/a1", "/root/c/c1"])
  }

  func testCancelScanCancelsInFlightInsightsTask() async {
    let root = FileNode(name: "root", path: "/tmp/root", isDirectory: true, sizeBytes: 128)
    let scanner = ImmediateScanner(node: root)
    let analyzer = SlowCancelableAnalyzer()
    let model = AppModel(scanner: scanner, analyzer: analyzer)
    let target = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

    model.selectScanTarget(target)
    model.startScan()

    await waitForRootNode(model, expectedPath: "/tmp/root")
    model.cancelScan()

    var didObserveCancellation = false
    for _ in 0..<80 {
      if await analyzer.cancellationObserved() {
        didObserveCancellation = true
        break
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertTrue(didObserveCancellation)
    XCTAssertTrue(model.insights.isEmpty)
  }

  func testScanPublishesPartialResultsWarningFromDiagnostics() async {
    let root = FileNode(name: "root", path: "/tmp/root", isDirectory: true, sizeBytes: 128)
    let diagnostics = ScanDiagnostics(
      skippedItemCount: 2,
      sampledSkippedPaths: ["/tmp/root/private"]
    )
    let scanner = ImmediateScannerWithDiagnostics(node: root, diagnostics: diagnostics)
    let analyzer = ControlledAnalyzer(output: [])
    let model = AppModel(scanner: scanner, analyzer: analyzer)
    let target = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

    model.selectScanTarget(target)
    model.startScan()
    await waitForRootNode(model, expectedPath: "/tmp/root")

    XCTAssertNotNil(model.scanWarningMessage)
    XCTAssertTrue(model.scanWarningMessage?.contains("skipped 2 unreadable items") == true)
  }

  func testScanUsesSelectedSizeStrategy() async {
    let root = FileNode(name: "root", path: "/tmp/root", isDirectory: true, sizeBytes: 128)
    let scanner = StrategyCapturingScanner(node: root)
    let analyzer = ControlledAnalyzer(output: [])
    let model = AppModel(scanner: scanner, analyzer: analyzer)
    let target = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

    model.scanSizeStrategy = .logical
    model.selectScanTarget(target)
    model.startScan()
    await waitForRootNode(model, expectedPath: "/tmp/root")

    let capturedStrategy = await scanner.lastCapturedStrategy()
    let didUseLegacyMethod = await scanner.didUseLegacyMethod()

    XCTAssertEqual(capturedStrategy, .logical)
    XCTAssertFalse(didUseLegacyMethod)
  }

  func testTopConsumersStoreRefreshesWhenTreeChangesButRootSummaryMatches() async {
    let store = TopConsumersStore()
    let rootA = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 300,
      children: [
        FileNode(
          name: "a",
          path: "/root/a",
          isDirectory: true,
          sizeBytes: 150,
          children: [
            FileNode(name: "a1", path: "/root/a/a1", isDirectory: false, sizeBytes: 150),
          ]
        ),
        FileNode(
          name: "b",
          path: "/root/b",
          isDirectory: true,
          sizeBytes: 150,
          children: [
            FileNode(name: "b1", path: "/root/b/b1", isDirectory: false, sizeBytes: 149),
            FileNode(name: "b2", path: "/root/b/b2", isDirectory: false, sizeBytes: 1),
          ]
        )
      ]
    )

    store.prepare(for: rootA, limit: 1)
    store.mode = .deepestConsumers
    await waitUntil("deepest entries should be computed for rootA") {
      store.entriesByMode[.deepestConsumers] != nil
    }
    XCTAssertEqual(store.visibleEntries(limit: 1).first?.node.path, "/root/a/a1")

    let rootB = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 300,
      children: [
        FileNode(
          name: "a",
          path: "/root/a",
          isDirectory: true,
          sizeBytes: 150,
          children: [
            FileNode(name: "a1", path: "/root/a/a1", isDirectory: false, sizeBytes: 149),
            FileNode(name: "a2", path: "/root/a/a2", isDirectory: false, sizeBytes: 1),
          ]
        ),
        FileNode(
          name: "b",
          path: "/root/b",
          isDirectory: true,
          sizeBytes: 150,
          children: [
            FileNode(name: "b1", path: "/root/b/b1", isDirectory: false, sizeBytes: 150),
          ]
        )
      ]
    )

    store.prepare(for: rootB, limit: 1)
    await waitUntil("deepest entries should refresh for rootB") {
      store.entriesByMode[.deepestConsumers] != nil &&
        store.visibleEntries(limit: 1).first?.node.path == "/root/b/b1"
    }

    XCTAssertEqual(store.visibleEntries(limit: 1).first?.node.path, "/root/b/b1")
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

  private func waitUntil(_ message: String, condition: () -> Bool) async {
    for _ in 0..<120 {
      if condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition: \(message)")
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
    userDefaults.removeObject(forKey: PersistedState.fullDiskScanDisclosureAcknowledgedKey)
  }
}
