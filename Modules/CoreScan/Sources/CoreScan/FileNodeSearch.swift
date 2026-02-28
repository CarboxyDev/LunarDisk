public struct FileNodeSearchMatch: Sendable {
  public let node: FileNode
  public let depth: Int
}

public struct FileNodeSearchResult: Sendable {
  public let matches: [FileNodeSearchMatch]
  public let totalMatchCount: Int
  public let totalMatchBytes: Int64
  public let matchedPaths: Set<String>
}

public enum FileNodeSearch {
  /// Searches the file tree for nodes whose name contains `query` (case-insensitive).
  /// Returns up to `limit` matches sorted by size descending, plus uncapped aggregate stats.
  public static func search(
    in root: FileNode,
    query: String,
    limit: Int = 200
  ) -> FileNodeSearchResult {
    guard !query.isEmpty else {
      return FileNodeSearchResult(matches: [], totalMatchCount: 0, totalMatchBytes: 0, matchedPaths: [])
    }

    var topMatches: [FileNodeSearchMatch] = []
    topMatches.reserveCapacity(min(limit, 256))
    var totalCount = 0
    var totalBytes: Int64 = 0
    var paths: Set<String> = []

    var stack: [(node: FileNode, depth: Int)] = [(root, 0)]

    while let current = stack.popLast() {
      if Task.isCancelled {
        break
      }

      if current.node.name.localizedCaseInsensitiveContains(query) {
        totalCount += 1
        totalBytes += current.node.sizeBytes
        paths.insert(current.node.path)
        insertMatch(FileNodeSearchMatch(node: current.node, depth: current.depth), into: &topMatches, limit: limit)
      }

      if current.node.isDirectory {
        for child in current.node.children {
          stack.append((child, current.depth + 1))
        }
      }
    }

    return FileNodeSearchResult(
      matches: topMatches,
      totalMatchCount: totalCount,
      totalMatchBytes: totalBytes,
      matchedPaths: paths
    )
  }

  private static func insertMatch(_ match: FileNodeSearchMatch, into top: inout [FileNodeSearchMatch], limit: Int) {
    guard limit > 0 else { return }
    if top.count == limit, let last = top.last, match.node.sizeBytes <= last.node.sizeBytes {
      return
    }

    var low = 0
    var high = top.count
    while low < high {
      let mid = (low + high) / 2
      if top[mid].node.sizeBytes < match.node.sizeBytes {
        high = mid
      } else {
        low = mid + 1
      }
    }
    top.insert(match, at: low)

    if top.count > limit {
      top.removeLast()
    }
  }
}
