import CoreGraphics
import CoreScan
import Foundation
import os

private let treemapSignposter = OSSignposter(subsystem: "com.lunardisk.perf", category: "TreemapLayout")

public enum TreemapLayout {
  public static func makeCells(
    from root: FileNode,
    maxDepth: Int = 3,
    maxChildrenPerNode: Int = 32,
    minVisibleFraction: Double = 0.003,
    maxCellCount: Int = 2_400
  ) -> [TreemapCell] {
    let signpostState = treemapSignposter.beginInterval("makeCells", "maxDepth=\(maxDepth) maxCells=\(maxCellCount)")

    guard root.sizeBytes > 0 else {
      treemapSignposter.endInterval("makeCells", signpostState)
      return []
    }
    guard maxDepth > 0 else {
      treemapSignposter.endInterval("makeCells", signpostState)
      return []
    }
    guard maxCellCount > 0 else {
      treemapSignposter.endInterval("makeCells", signpostState)
      return []
    }

    var cells: [TreemapCell] = []
    var remainingCellBudget = maxCellCount
    appendChildren(
      of: root,
      in: CGRect(x: 0, y: 0, width: 1, height: 1),
      depth: 1,
      maxDepth: maxDepth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction,
      remainingCellBudget: &remainingCellBudget,
      into: &cells
    )
    treemapSignposter.emitEvent("makeCells.result", "\(cells.count) cells")
    treemapSignposter.endInterval("makeCells", signpostState)
    return cells
  }

  private static func appendChildren(
    of node: FileNode,
    in rect: CGRect,
    depth: Int,
    maxDepth: Int,
    maxChildrenPerNode: Int,
    minVisibleFraction: Double,
    remainingCellBudget: inout Int,
    into cells: inout [TreemapCell]
  ) {
    guard depth <= maxDepth else { return }
    guard remainingCellBudget > 0 else { return }
    let entries = makeEntries(
      for: node,
      depth: depth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction
    )
    guard !entries.isEmpty else { return }

    let layoutRect = rect.insetBy(
      dx: min(rect.width, rect.height) * 0.004,
      dy: min(rect.width, rect.height) * 0.004
    )
    guard layoutRect.width > 0, layoutRect.height > 0 else { return }

    let sumSizes = entries.reduce(Int64(0)) { partialResult, entry in
      partialResult + max(0, entry.sizeBytes)
    }
    guard sumSizes > 0 else { return }

    let totalArea = layoutRect.width * layoutRect.height
    let items = entries.map { entry in
      SquarifyItem(
        entry: entry,
        area: (CGFloat(entry.sizeBytes) / CGFloat(sumSizes)) * totalArea
      )
    }
    let placements = squarify(items: items, in: layoutRect)

    for placement in placements {
      guard remainingCellBudget > 0 else { return }
      let entry = placement.item.entry
      guard placement.rect.width > 0, placement.rect.height > 0 else { continue }

      cells.append(
        TreemapCell(
          id: entry.id,
          rect: placement.rect,
          depth: depth,
          sizeBytes: entry.sizeBytes,
          label: entry.label,
          path: entry.path,
          isDirectory: entry.isDirectory,
          isAggregate: entry.isAggregate
        )
      )
      remainingCellBudget -= 1

      if entry.isDirectory, !entry.isAggregate, let childNode = entry.node {
        appendChildren(
          of: childNode,
          in: placement.rect,
          depth: depth + 1,
          maxDepth: maxDepth,
          maxChildrenPerNode: maxChildrenPerNode,
          minVisibleFraction: minVisibleFraction,
          remainingCellBudget: &remainingCellBudget,
          into: &cells
        )
      }
    }
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
    selected.reserveCapacity(min(sortedChildren.count, maxChildrenPerNode))
    var overflowSizeBytes: Int64 = 0
    let denominator = Double(max(node.sizeBytes, 1))

    for (index, child) in sortedChildren.enumerated() {
      let fraction = Double(child.sizeBytes) / denominator
      let shouldKeep = selected.count < maxChildrenPerNode && (fraction >= minVisibleFraction || index < 6)
      if shouldKeep {
        selected.append(LayoutEntry(node: child))
      } else {
        overflowSizeBytes += child.sizeBytes
      }
    }

    if overflowSizeBytes > 0 {
      selected.append(
        LayoutEntry(
          id: "\(node.path)#other-depth-\(depth)",
          label: "Other",
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

  private static func squarify(items: [SquarifyItem], in rect: CGRect) -> [Placement] {
    let signpostState = treemapSignposter.beginInterval("squarify", "\(items.count) items")
    defer { treemapSignposter.endInterval("squarify", signpostState) }
    guard !items.isEmpty else { return [] }

    var sortedItems = items.sorted { lhs, rhs in
      lhs.area > rhs.area
    }
    var remainingRect = rect
    var row: [SquarifyItem] = []
    var placements: [Placement] = []

    while let next = sortedItems.first {
      let shortSide = min(remainingRect.width, remainingRect.height)
      if row.isEmpty || worstAspectRatio(for: row + [next], shortSide: shortSide) <= worstAspectRatio(for: row, shortSide: shortSide) {
        row.append(next)
        sortedItems.removeFirst()
      } else {
        placements.append(contentsOf: layout(row: row, in: &remainingRect))
        row.removeAll(keepingCapacity: true)
      }
    }

    if !row.isEmpty {
      placements.append(contentsOf: layout(row: row, in: &remainingRect))
    }

    return placements
  }

  private static func layout(row: [SquarifyItem], in remainingRect: inout CGRect) -> [Placement] {
    guard !row.isEmpty else { return [] }

    let rowArea = row.reduce(CGFloat(0)) { partialResult, item in
      partialResult + item.area
    }
    guard rowArea > 0 else { return [] }

    var placements: [Placement] = []
    placements.reserveCapacity(row.count)

    if remainingRect.width >= remainingRect.height {
      let rowHeight = rowArea / max(remainingRect.width, 0.0001)
      var xCursor = remainingRect.minX

      for item in row {
        let width = item.area / max(rowHeight, 0.0001)
        placements.append(
          Placement(
            item: item,
            rect: CGRect(
              x: xCursor,
              y: remainingRect.minY,
              width: width,
              height: rowHeight
            )
          )
        )
        xCursor += width
      }

      remainingRect = CGRect(
        x: remainingRect.minX,
        y: remainingRect.minY + rowHeight,
        width: remainingRect.width,
        height: max(remainingRect.height - rowHeight, 0)
      )
    } else {
      let rowWidth = rowArea / max(remainingRect.height, 0.0001)
      var yCursor = remainingRect.minY

      for item in row {
        let height = item.area / max(rowWidth, 0.0001)
        placements.append(
          Placement(
            item: item,
            rect: CGRect(
              x: remainingRect.minX,
              y: yCursor,
              width: rowWidth,
              height: height
            )
          )
        )
        yCursor += height
      }

      remainingRect = CGRect(
        x: remainingRect.minX + rowWidth,
        y: remainingRect.minY,
        width: max(remainingRect.width - rowWidth, 0),
        height: remainingRect.height
      )
    }

    return placements
  }

  private static func worstAspectRatio(for row: [SquarifyItem], shortSide: CGFloat) -> CGFloat {
    guard !row.isEmpty, shortSide > 0 else { return .infinity }

    let sum = row.reduce(CGFloat(0)) { partialResult, item in
      partialResult + item.area
    }
    guard sum > 0 else { return .infinity }

    let minArea = row.map(\.area).min() ?? 0
    let maxArea = row.map(\.area).max() ?? 0
    guard minArea > 0, maxArea > 0 else { return .infinity }

    let shortSideSquared = shortSide * shortSide
    let sumSquared = sum * sum

    let ratioA = (shortSideSquared * maxArea) / sumSquared
    let ratioB = sumSquared / (shortSideSquared * minArea)
    return max(ratioA, ratioB)
  }
}

private struct LayoutEntry: Hashable {
  let id: String
  let label: String
  let path: String?
  let isDirectory: Bool
  let isAggregate: Bool
  let sizeBytes: Int64
  let node: FileNode?

  init(node: FileNode) {
    id = node.path
    label = node.name
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

private struct SquarifyItem {
  let entry: LayoutEntry
  let area: CGFloat
}

private struct Placement {
  let item: SquarifyItem
  let rect: CGRect
}
