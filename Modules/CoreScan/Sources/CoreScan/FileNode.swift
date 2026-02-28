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

extension FileNode {
  /// Returns a new tree with the given paths removed and sizes recomputed.
  /// If this node itself is in the removed set, returns nil.
  public func pruning(paths: Set<String>) -> FileNode? {
    guard !paths.contains(path) else { return nil }

    let prunedChildren = children.compactMap { $0.pruning(paths: paths) }

    if prunedChildren.count == children.count,
       prunedChildren.elementsEqual(children, by: { $0.path == $1.path && $0.sizeBytes == $1.sizeBytes })
    {
      return self
    }

    let newSize: Int64
    if isDirectory {
      newSize = prunedChildren.reduce(0) { $0 + $1.sizeBytes }
    } else {
      newSize = sizeBytes
    }

    return FileNode(
      name: name,
      path: path,
      isDirectory: isDirectory,
      sizeBytes: newSize,
      children: prunedChildren
    )
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
