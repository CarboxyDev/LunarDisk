import Foundation

public struct FileNode: Identifiable, Sendable {
  public let name: String
  public let path: String
  public let isDirectory: Bool
  public let sizeBytes: Int64
  public let children: [FileNode]
  public let sortedChildrenBySize: [FileNode]

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
    self.sortedChildrenBySize = children.sorted { lhs, rhs in
      if lhs.sizeBytes != rhs.sizeBytes {
        return lhs.sizeBytes > rhs.sizeBytes
      }
      if lhs.name != rhs.name {
        return lhs.name < rhs.name
      }
      return lhs.path < rhs.path
    }
  }
}

extension FileNode: Equatable {
  public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
    lhs.path == rhs.path
      && lhs.sizeBytes == rhs.sizeBytes
  }
}

extension FileNode: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(path)
    hasher.combine(sizeBytes)
  }
}
