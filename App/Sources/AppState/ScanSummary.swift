import CoreScan
import Foundation

struct ScanSummaryTopItem: Codable, Equatable, Sendable {
  let name: String
  let path: String
  let sizeBytes: Int64
}

struct ScanSummary: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let targetPath: String
  let timestamp: Date
  let totalSizeBytes: Int64
  let totalFileCount: Int
  let totalDirectoryCount: Int
  let topItems: [ScanSummaryTopItem]

  init(
    id: UUID = UUID(),
    targetPath: String,
    timestamp: Date = Date(),
    totalSizeBytes: Int64,
    totalFileCount: Int,
    totalDirectoryCount: Int,
    topItems: [ScanSummaryTopItem]
  ) {
    self.id = id
    self.targetPath = targetPath
    self.timestamp = timestamp
    self.totalSizeBytes = totalSizeBytes
    self.totalFileCount = totalFileCount
    self.totalDirectoryCount = totalDirectoryCount
    self.topItems = topItems
  }

  static func from(rootNode: FileNode, targetPath: String) -> ScanSummary {
    let counts = countNodes(rootNode)
    let top5 = rootNode.sortedChildrenBySize
      .prefix(5)
      .map { ScanSummaryTopItem(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes) }

    return ScanSummary(
      targetPath: targetPath,
      totalSizeBytes: rootNode.sizeBytes,
      totalFileCount: counts.files,
      totalDirectoryCount: counts.directories,
      topItems: Array(top5)
    )
  }

  private static func countNodes(_ node: FileNode) -> (files: Int, directories: Int) {
    var files = 0
    var directories = 0
    var stack: [FileNode] = [node]

    while let current = stack.popLast() {
      if current.isDirectory {
        directories += 1
        stack.append(contentsOf: current.children)
      } else {
        files += 1
      }
    }

    return (files, directories)
  }
}
