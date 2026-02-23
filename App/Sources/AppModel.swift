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

  private let scanner: DirectoryScanner
  private let analyzer: HeuristicAnalyzer
  private var scanTask: Task<Void, Never>?

  init(
    scanner: DirectoryScanner = DirectoryScanner(),
    analyzer: HeuristicAnalyzer = HeuristicAnalyzer()
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

    scanTask = Task { [weak self] in
      await self?.scan(url: selectedURL)
    }
  }

  func cancelScan() {
    scanTask?.cancel()
    isScanning = false
  }

  private func scan(url: URL) async {
    isScanning = true
    errorMessage = nil
    insights = []
    lastFailure = nil

    do {
      let scannedRoot = try await scanner.scan(at: url, maxDepth: 8)
      if Task.isCancelled { return }

      rootNode = scannedRoot
      insights = await analyzer.generateInsights(for: scannedRoot)
    } catch {
      if Task.isCancelled { return }
      rootNode = nil
      errorMessage = error.localizedDescription
      lastFailure = classify(error: error)
    }

    isScanning = false
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
