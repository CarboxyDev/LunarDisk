import CoreScan
import Foundation
import LunardiskAI

@MainActor
final class AppModel: ObservableObject {
  @Published var selectedURL: URL?
  @Published var rootNode: FileNode?
  @Published var insights: [Insight] = []
  @Published var isScanning = false
  @Published var errorMessage: String?

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

    do {
      let scannedRoot = try await scanner.scan(at: url, maxDepth: 8)
      if Task.isCancelled { return }

      rootNode = scannedRoot
      insights = await analyzer.generateInsights(for: scannedRoot)
    } catch {
      if Task.isCancelled { return }
      rootNode = nil
      errorMessage = error.localizedDescription
    }

    isScanning = false
  }
}

