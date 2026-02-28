import CoreScan
import Foundation

public enum RadialBreakdownLayout {
  public static func makeArcs(
    from root: FileNode,
    maxDepth: Int = 5,
    maxChildrenPerNode: Int = 16,
    minVisibleFraction: Double = 0.007,
    maxArcCount: Int = 3_200
  ) -> [RadialBreakdownArc] {
    guard root.sizeBytes > 0 else { return [] }
    guard maxDepth > 0 else { return [] }
    guard maxArcCount > 0 else { return [] }

    let start = -Double.pi / 2
    let end = (3 * Double.pi) / 2
    var arcs: [RadialBreakdownArc] = [
      RadialBreakdownArc(
        id: root.id,
        parentID: nil,
        startAngle: start,
        endAngle: end,
        depth: 0,
        sizeBytes: root.sizeBytes,
        label: root.name,
        path: root.path,
        isDirectory: true,
        isAggregate: false,
        branchIndex: 0
      )
    ]

    var remainingArcBudget = maxArcCount - 1
    appendChildren(
      of: root,
      parentID: root.id,
      depth: 1,
      startAngle: start,
      endAngle: end,
      inheritedBranchIndex: nil,
      maxDepth: maxDepth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction,
      remainingArcBudget: &remainingArcBudget,
      into: &arcs
    )
    return arcs
  }

  private static func appendChildren(
    of node: FileNode,
    parentID: String,
    depth: Int,
    startAngle: Double,
    endAngle: Double,
    inheritedBranchIndex: Int?,
    maxDepth: Int,
    maxChildrenPerNode: Int,
    minVisibleFraction: Double,
    remainingArcBudget: inout Int,
    into arcs: inout [RadialBreakdownArc]
  ) {
    guard depth <= maxDepth else { return }
    guard remainingArcBudget > 0 else { return }

    let entries = makeEntries(
      for: node,
      depth: depth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction
    )
    guard !entries.isEmpty else { return }

    let totalBytes = entries.reduce(Int64(0)) { partialResult, entry in
      partialResult + max(0, entry.sizeBytes)
    }
    guard totalBytes > 0 else { return }

    let span = endAngle - startAngle
    var cursor = startAngle

    for (index, entry) in entries.enumerated() {
      guard remainingArcBudget > 0 else { return }
      guard entry.sizeBytes > 0 else { continue }

      let childSpan = (Double(entry.sizeBytes) / Double(totalBytes)) * span
      let childEnd = cursor + childSpan
      let branchIndex = inheritedBranchIndex ?? index

      arcs.append(
        RadialBreakdownArc(
          id: entry.id,
          parentID: parentID,
          startAngle: cursor,
          endAngle: childEnd,
          depth: depth,
          sizeBytes: entry.sizeBytes,
          label: entry.label,
          path: entry.path,
          isDirectory: entry.isDirectory,
          isAggregate: entry.isAggregate,
          branchIndex: branchIndex
        )
      )
      remainingArcBudget -= 1

      if
        let childNode = entry.node,
        childNode.isDirectory,
        !childNode.children.isEmpty,
        shouldExpand(childNode, depth: depth)
      {
        appendChildren(
          of: childNode,
          parentID: entry.id,
          depth: depth + 1,
          startAngle: cursor,
          endAngle: childEnd,
          inheritedBranchIndex: branchIndex,
          maxDepth: maxDepth,
          maxChildrenPerNode: maxChildrenPerNode,
          minVisibleFraction: minVisibleFraction,
          remainingArcBudget: &remainingArcBudget,
          into: &arcs
        )
      }

      cursor = childEnd
    }
  }

  // Deep linear chains produce visually noisy rings with little information.
  // Expand only when a directory has branching, or when still near the root.
  private static func shouldExpand(_ node: FileNode, depth: Int) -> Bool {
    var nonZeroCount = 0
    for child in node.children {
      if child.sizeBytes > 0 {
        nonZeroCount += 1
        if depth <= 2 { return true }
        if nonZeroCount > 1 { return true }
      }
    }
    return false
  }

  private static func makeEntries(
    for node: FileNode,
    depth: Int,
    maxChildrenPerNode: Int,
    minVisibleFraction: Double
  ) -> [LayoutEntry] {
    guard node.sizeBytes > 0 else { return [] }

    let sortedChildren = node.sortedChildrenBySize.filter { $0.sizeBytes > 0 }
    guard !sortedChildren.isEmpty else { return [] }

    var selected: [LayoutEntry] = []
    selected.reserveCapacity(min(maxChildrenPerNode, sortedChildren.count))
    var overflowSizeBytes: Int64 = 0
    let denominator = Double(max(node.sizeBytes, 1))

    for (index, child) in sortedChildren.enumerated() {
      let fraction = Double(child.sizeBytes) / denominator
      let shouldKeep = selected.count < maxChildrenPerNode && (fraction >= minVisibleFraction || index < 5)
      if shouldKeep {
        selected.append(LayoutEntry(node: child))
      } else {
        overflowSizeBytes += child.sizeBytes
      }
    }

    if overflowSizeBytes > 0 {
      selected.append(
        LayoutEntry(
          id: "\(node.path)#smaller-\(depth)",
          label: "Smaller objects...",
          path: nil,
          isDirectory: true,
          isAggregate: true,
          sizeBytes: overflowSizeBytes,
          node: nil
        )
      )
    }

    return selected
  }
}

private struct LayoutEntry {
  let id: String
  let label: String
  let path: String?
  let isDirectory: Bool
  let isAggregate: Bool
  let sizeBytes: Int64
  let node: FileNode?

  init(node: FileNode) {
    id = node.path
    let preferredLabel = node.name.isEmpty ? URL(fileURLWithPath: node.path).lastPathComponent : node.name
    label = sanitizedLabel(preferredLabel, fallbackPath: node.path)
    path = node.path
    isDirectory = node.isDirectory
    isAggregate = false
    sizeBytes = node.sizeBytes
    self.node = node
  }

  init(
    id: String,
    label: String,
    path: String?,
    isDirectory: Bool,
    isAggregate: Bool,
    sizeBytes: Int64,
    node: FileNode?
  ) {
    self.id = id
    self.label = label
    self.path = path
    self.isDirectory = isDirectory
    self.isAggregate = isAggregate
    self.sizeBytes = sizeBytes
    self.node = node
  }
}

private func sanitizedLabel(_ rawLabel: String, fallbackPath: String) -> String {
  let cleanedLabel = rawLabel
    .replacingOccurrences(of: "\n", with: " ")
    .replacingOccurrences(of: "\r", with: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if !cleanedLabel.isEmpty {
    return cleanedLabel
  }

  let fallbackLabel = URL(fileURLWithPath: fallbackPath).lastPathComponent
    .replacingOccurrences(of: "\n", with: " ")
    .replacingOccurrences(of: "\r", with: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if !fallbackLabel.isEmpty {
    return fallbackLabel
  }

  let cleanedPath = fallbackPath
    .replacingOccurrences(of: "\n", with: " ")
    .replacingOccurrences(of: "\r", with: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  return cleanedPath.isEmpty ? "Unknown" : cleanedPath
}
