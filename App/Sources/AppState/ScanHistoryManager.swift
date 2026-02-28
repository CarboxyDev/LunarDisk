import Foundation

final class ScanHistoryManager: @unchecked Sendable {
  static let shared = ScanHistoryManager()

  private static let maxEntries = 50

  private let fileURL: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("com.lunardisk.app", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("scan-history.json")
  }()

  private let queue = DispatchQueue(label: "com.lunardisk.scan-history", qos: .utility)
  private var cachedHistory: [ScanSummary]?

  private init() {}

  func load() -> [ScanSummary] {
    if let cached = cachedHistory {
      return cached
    }
    let loaded = loadFromDisk()
    cachedHistory = loaded
    return loaded
  }

  func save(_ summary: ScanSummary) {
    var history = load()
    history.append(summary)
    if history.count > Self.maxEntries {
      history = Array(history.suffix(Self.maxEntries))
    }
    cachedHistory = history
    let snapshot = history
    queue.async { [fileURL] in
      Self.writeToDisk(snapshot, at: fileURL)
    }
  }

  func recentScans(limit: Int = 5) -> [ScanSummary] {
    Array(load().suffix(limit).reversed())
  }

  func previousSummary(for targetPath: String, excluding currentID: UUID? = nil) -> ScanSummary? {
    load()
      .filter { $0.targetPath == targetPath && $0.id != currentID }
      .last
  }

  private func loadFromDisk() -> [ScanSummary] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode([ScanSummary].self, from: data)
    } catch {
      return []
    }
  }

  private static func writeToDisk(_ history: [ScanSummary], at url: URL) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(history)
      try data.write(to: url, options: .atomic)
    } catch {
      // Silently fail — scan history is non-critical
    }
  }
}
