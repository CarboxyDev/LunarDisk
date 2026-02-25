import CoreScan
import Foundation
import LunardiskAI

@MainActor
final class AppModel: ObservableObject {
  enum ScanFailure: Equatable {
    case permissionDenied(path: String)
    case notFound(path: String)
    case unreadable(path: String, message: String)
    case unknown(message: String)
  }

  @Published var selectedURL: URL?
  @Published var rootNode: FileNode?
  @Published var insights: [Insight] = []
  @Published var isScanning = false
  @Published var errorMessage: String?
  @Published var lastFailure: ScanFailure?
  @Published var scanWarningMessage: String?
  @Published var scanProgress: ScanProgress?
  // Internal-only toggle for scan sizing semantics until we add an advanced settings UI.
  var scanSizeStrategy: ScanSizeStrategy = .allocated

  private let scanner: any FileScanning
  private let analyzer: any AIAnalyzing
  private var scanTask: Task<Void, Never>?
  private var insightsTask: Task<[Insight], Never>?
  private var activeScanID: UUID?

  init(
    scanner: any FileScanning = DirectoryScanner(),
    analyzer: any AIAnalyzing = HeuristicAnalyzer()
  ) {
    self.scanner = scanner
    self.analyzer = analyzer
  }

  deinit {
    scanTask?.cancel()
    insightsTask?.cancel()
  }

  var canStartScan: Bool {
    selectedURL != nil && !isScanning
  }

  func selectScanTarget(_ url: URL?) {
    selectedURL = url
    rootNode = nil
    insights = []
    errorMessage = nil
    lastFailure = nil
    scanWarningMessage = nil
  }

  func scanMacintoshHD() {
    selectScanTarget(URL(fileURLWithPath: "/", isDirectory: true))
    startScan()
  }

  func startScan() {
    guard let selectedURL else { return }
    scanTask?.cancel()
    scanTask = nil
    insightsTask?.cancel()
    insightsTask = nil
    let scanID = UUID()
    activeScanID = scanID

    scanTask = Task { [weak self] in
      await self?.scan(url: selectedURL, scanID: scanID)
    }
  }

  func cancelScan() {
    activeScanID = nil
    scanTask?.cancel()
    scanTask = nil
    insightsTask?.cancel()
    insightsTask = nil
    isScanning = false
    scanWarningMessage = nil
    scanProgress = nil
  }

  private func scan(url: URL, scanID: UUID) async {
    guard activeScanID == scanID, !Task.isCancelled else { return }
    isScanning = true
    defer {
      if activeScanID == scanID {
        isScanning = false
        scanProgress = nil
        scanTask = nil
        activeScanID = nil
      }
    }
    errorMessage = nil
    insights = []
    lastFailure = nil
    scanWarningMessage = nil
    scanProgress = nil

    let progressScanID = scanID
    let progressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
      Task { @MainActor [weak self] in
        guard let self, self.activeScanID == progressScanID else { return }
        self.scanProgress = progress
      }
    }

    do {
      try Task.checkCancellation()
      let scannedRoot = try await scanner.scan(
        at: url,
        maxDepth: 8,
        sizeStrategy: scanSizeStrategy,
        onProgress: progressHandler
      )
      try Task.checkCancellation()
      guard activeScanID == scanID else { return }

      rootNode = scannedRoot
      let diagnostics = await scanner.lastScanDiagnostics()
      guard activeScanID == scanID else { return }
      scanWarningMessage = Self.warningMessage(from: diagnostics)
      isScanning = false

      let analyzer = self.analyzer
      let insightsTask = Task.detached(priority: .utility) {
        await analyzer.generateInsights(for: scannedRoot)
      }
      self.insightsTask = insightsTask
      let generatedInsights = await insightsTask.value
      self.insightsTask = nil

      try Task.checkCancellation()
      guard activeScanID == scanID else { return }

      insights = generatedInsights
    } catch is CancellationError {
      return
    } catch {
      guard activeScanID == scanID else { return }
      if Task.isCancelled { return }
      rootNode = nil
      errorMessage = error.localizedDescription
      lastFailure = classify(error: error)
      scanWarningMessage = nil
    }
  }

  private func classify(error: Error) -> ScanFailure {
    if let scanError = error as? ScanError {
      switch scanError {
      case let .notFound(path):
        return .notFound(path: path)
      case let .unreadable(path, underlying):
        if Self.isPermissionDenied(error: underlying) {
          return .permissionDenied(path: path)
        }
        return .unreadable(path: path, message: underlying.localizedDescription)
      }
    }

    if Self.isPermissionDenied(error: error) {
      return .permissionDenied(path: selectedURL?.path ?? "/")
    }

    return .unknown(message: error.localizedDescription)
  }

  private static func isPermissionDenied(error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
      return true
    }
    if nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EACCES) || nsError.code == Int(EPERM)) {
      return true
    }
    return false
  }

  private static func warningMessage(from diagnostics: ScanDiagnostics?) -> String? {
    guard let diagnostics, diagnostics.isPartialResult else {
      return nil
    }
    let skippedCount = diagnostics.skippedItemCount
    if let firstSample = diagnostics.sampledSkippedPaths.first {
      let suffix = skippedCount == 1 ? "" : "s"
      return "Partial scan: skipped \(skippedCount) unreadable item\(suffix). Totals may be lower than actual usage. Example: \(firstSample)"
    }
    let suffix = skippedCount == 1 ? "" : "s"
    return "Partial scan: skipped \(skippedCount) unreadable item\(suffix). Totals may be lower than actual usage."
  }
}
