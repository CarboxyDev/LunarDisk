import Foundation

public struct FileNode: Identifiable, Hashable, Sendable {
  public let name: String
  public let path: String
  public let isDirectory: Bool
  public let sizeBytes: Int64
  public let children: [FileNode]

  public var id: String { path }

  public init(
    name: String,
    path: String,
    isDirectory: Bool,
    sizeBytes: Int64,
    children: [FileNode] = []
  ) {
    self.name = name
    self.path = path
    self.isDirectory = isDirectory
    self.sizeBytes = sizeBytes
    self.children = children
  }
}

public extension FileNode {
  var sortedChildrenBySize: [FileNode] {
    children.sorted { lhs, rhs in
      lhs.sizeBytes > rhs.sizeBytes
    }
  }
}

