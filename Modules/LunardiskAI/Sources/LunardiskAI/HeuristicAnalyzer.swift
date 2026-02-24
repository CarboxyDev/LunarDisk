import CoreScan
import Foundation

public protocol AIAnalyzing: Sendable {
  func generateInsights(for root: FileNode) async -> [Insight]
}

public struct HeuristicAnalyzer: AIAnalyzing {
  public init() {}

  public func generateInsights(for root: FileNode) async -> [Insight] {
    if Task.isCancelled {
      return []
    }

    guard root.sizeBytes > 0 else {
      return [Insight(severity: .info, message: "Selected folder is empty.")]
    }

    var insights: [Insight] = []
    let sortedChildren = root.sortedChildrenBySize

    if let largest = sortedChildren.first {
      let ratio = Double(largest.sizeBytes) / Double(max(root.sizeBytes, 1))
      let percent = Int((ratio * 100).rounded())
      let severity: InsightSeverity = ratio > 0.5 ? .warning : .info
      insights.append(
        Insight(
          severity: severity,
          message: "\"\(largest.name)\" uses \(percent)% of this folder."
        )
      )
    }

    let fileCount = recursiveFileCount(in: root)
    if Task.isCancelled {
      return []
    }
    if fileCount > 20_000 {
      insights.append(
        Insight(
          severity: .warning,
          message: "This scan includes \(fileCount) files. Cleanup candidates may be duplicated media or cache directories."
        )
      )
    } else {
      insights.append(
        Insight(
          severity: .info,
          message: "Scan includes \(fileCount) files."
        )
      )
    }

    if insights.isEmpty {
      insights.append(
        Insight(
          severity: .info,
          message: "No major anomalies detected by heuristic analysis."
        )
      )
    }

    return insights
  }

  private func recursiveFileCount(in node: FileNode) -> Int {
    if Task.isCancelled {
      return 0
    }

    if !node.isDirectory {
      return 1
    }
    return node.children.reduce(0) { partialResult, child in
      partialResult + recursiveFileCount(in: child)
    }
  }
}
