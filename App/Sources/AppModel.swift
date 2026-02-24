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

  private let scanner: any FileScanning
  private let analyzer: any AIAnalyzing
  private var scanTask: Task<Void, Never>?
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
  }

  func scanMacintoshHD() {
    selectScanTarget(URL(fileURLWithPath: "/", isDirectory: true))
    startScan()
  }

  func startScan() {
    guard let selectedURL else { return }
    scanTask?.cancel()
    scanTask = nil
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
    isScanning = false
  }

  private func scan(url: URL, scanID: UUID) async {
    guard activeScanID == scanID, !Task.isCancelled else { return }
    isScanning = true
    defer {
      if activeScanID == scanID {
        isScanning = false
        scanTask = nil
        activeScanID = nil
      }
    }
    errorMessage = nil
    insights = []
    lastFailure = nil

    do {
      try Task.checkCancellation()
      let scannedRoot = try await scanner.scan(at: url, maxDepth: 8)
      try Task.checkCancellation()
      guard activeScanID == scanID else { return }

      rootNode = scannedRoot
      isScanning = false

      let analyzer = self.analyzer
      let generatedInsights = await Task.detached(priority: .utility) {
        await analyzer.generateInsights(for: scannedRoot)
      }.value

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
}
