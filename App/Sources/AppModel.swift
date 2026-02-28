import CoreScan
import Foundation
import LunardiskAI
import os

private let pipelineSignposter = OSSignposter(subsystem: "com.lunardisk.perf", category: "Pipeline")

@MainActor
final class AppModel: ObservableObject {
  enum ScanFailure: Equatable {
    case permissionDenied(path: String)
    case notFound(path: String)
    case unreadable(path: String, message: String)
    case unknown(message: String)
  }

  struct VolumeCapacity {
    let totalBytes: Int64
    let availableBytes: Int64
    let availableForImportantUseBytes: Int64

    var purgeableBytes: Int64 {
      max(0, availableForImportantUseBytes - availableBytes)
    }
  }

  @Published var selectedURL: URL?
  @Published var rootNode: FileNode?
  @Published var insights: [Insight] = []
  @Published var isScanning = false
  @Published var errorMessage: String?
  @Published var lastFailure: ScanFailure?
  @Published var scanWarningMessage: String?
  @Published var scanProgress: ScanProgress?
  @Published var lastScanSummary: ScanSummary?
  @Published var previousSummaryForTarget: ScanSummary?
  @Published var volumeCapacity: VolumeCapacity?
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
    volumeCapacity = url.flatMap { Self.fetchVolumeCapacity(for: $0) }
  }

  func updateRootNode(_ newRoot: FileNode) {
    rootNode = newRoot
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

    let signpostState = pipelineSignposter.beginInterval("pipeline", "\(url.path)")

    isScanning = true
    defer {
      pipelineSignposter.endInterval("pipeline", signpostState)
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

    let (progressStream, progressContinuation) = AsyncStream.makeStream(of: ScanProgress.self)
    let progressTask = Task { @MainActor [weak self] in
      for await progress in progressStream {
        guard let self, self.activeScanID == scanID else { break }
        self.scanProgress = progress
      }
    }
    defer {
      progressContinuation.finish()
      progressTask.cancel()
    }

    do {
      try Task.checkCancellation()
      pipelineSignposter.emitEvent("pipeline.phase", "begin filesystem scan")
      let scannedRoot = try await scanner.scan(
        at: url,
        maxDepth: 8,
        sizeStrategy: scanSizeStrategy,
        onProgress: { progress in progressContinuation.yield(progress) }
      )
      try Task.checkCancellation()
      guard activeScanID == scanID else { return }

      pipelineSignposter.emitEvent("pipeline.phase", "scan complete, begin insights")
      rootNode = scannedRoot

      let summary = ScanSummary.from(rootNode: scannedRoot, targetPath: url.path)
      previousSummaryForTarget = ScanHistoryManager.shared.previousSummary(
        for: url.path, excluding: summary.id
      )
      ScanHistoryManager.shared.save(summary)
      lastScanSummary = summary

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

      pipelineSignposter.emitEvent("pipeline.phase", "insights complete")
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

  private static func fetchVolumeCapacity(for url: URL) -> VolumeCapacity? {
    let keys: Set<URLResourceKey> = [
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey
    ]
    guard let values = try? url.resourceValues(forKeys: keys),
          let total = values.volumeTotalCapacity,
          let available = values.volumeAvailableCapacity,
          let availableImportant = values.volumeAvailableCapacityForImportantUsage
    else {
      return nil
    }
    return VolumeCapacity(
      totalBytes: Int64(total),
      availableBytes: Int64(available),
      availableForImportantUseBytes: Int64(availableImportant)
    )
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
