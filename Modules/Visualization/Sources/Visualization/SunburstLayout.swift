import CoreScan
import Foundation

public enum SunburstLayout {
  public static func makeSegments(from root: FileNode) -> [SunburstSegment] {
    guard root.sizeBytes > 0 else { return [] }

    let start = -Double.pi / 2
    let end = (3 * Double.pi) / 2

    var segments: [SunburstSegment] = [
      SunburstSegment(
        id: root.id,
        startAngle: start,
        endAngle: end,
        depth: 0,
        sizeBytes: root.sizeBytes,
        label: root.name
      )
    ]

    appendChildren(
      of: root,
      depth: 1,
      startAngle: start,
      endAngle: end,
      into: &segments
    )

    return segments
  }

  private static func appendChildren(
    of node: FileNode,
    depth: Int,
    startAngle: Double,
    endAngle: Double,
    into segments: inout [SunburstSegment]
  ) {
    let span = endAngle - startAngle
    let denominator = max(Double(node.sizeBytes), 1)
    var cursor = startAngle

    for child in node.sortedChildrenBySize where child.sizeBytes > 0 {
      let childSpan = (Double(child.sizeBytes) / denominator) * span
      let childEnd = cursor + childSpan

      segments.append(
        SunburstSegment(
          id: child.id,
          startAngle: cursor,
          endAngle: childEnd,
          depth: depth,
          sizeBytes: child.sizeBytes,
          label: child.name
        )
      )

      if !child.children.isEmpty {
        appendChildren(
          of: child,
          depth: depth + 1,
          startAngle: cursor,
          endAngle: childEnd,
          into: &segments
        )
      }

      cursor = childEnd
    }
  }
}

