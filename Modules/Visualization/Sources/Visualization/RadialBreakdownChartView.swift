import CoreGraphics
import CoreScan
import SwiftUI

public struct RadialBreakdownChartView: View {
  private struct ChartMetrics {
    let center: CGPoint
    let chartRadius: CGFloat
    let donutRadius: CGFloat
    let ringBandWidth: CGFloat
    let drawingRect: CGRect

    func ringBounds(for depth: Int) -> (inner: CGFloat, outer: CGFloat) {
      let inner = donutRadius + (CGFloat(depth - 1) * ringBandWidth) + 2
      let outer = donutRadius + (CGFloat(depth) * ringBandWidth) - 2
      return (inner, max(inner + 0.8, outer))
    }
  }

  private static let defaultPalette: [Color] = [
    Color(red: 78 / 255, green: 168 / 255, blue: 230 / 255),
    Color(red: 104 / 255, green: 205 / 255, blue: 176 / 255),
    Color(red: 214 / 255, green: 144 / 255, blue: 88 / 255),
    Color(red: 184 / 255, green: 129 / 255, blue: 203 / 255),
    Color(red: 195 / 255, green: 171 / 255, blue: 90 / 255),
  ]

  private static let inspectorRowCapacity = 6

  private let rootSizeBytes: Int64
  private let rootArcID: String
  private let nonRootArcs: [RadialBreakdownArc]
  private let arcsByDepth: [Int: [RadialBreakdownArc]]
  private let arcsByID: [String: RadialBreakdownArc]
  private let parentIDsByID: [String: String?]
  private let childrenByParentID: [String: [RadialBreakdownArc]]
  private let baseColorByArcID: [String: Color]
  private let inspectorSnapshotByArcID: [String: RadialBreakdownInspectorSnapshot]
  private let palette: [Color]
  private let maxDepth: Int
  private let onPathActivated: ((String) -> Void)?
  private let pinnedArcID: String?
  private let onHoverSnapshotChanged: ((RadialBreakdownInspectorSnapshot?) -> Void)?
  private let onRootSnapshotReady: ((RadialBreakdownInspectorSnapshot?) -> Void)?

  @State private var hoveredArcID: String?

  public init(root: FileNode) {
    self.init(root: root, palette: Self.defaultPalette, onPathActivated: nil)
  }

  public init(
    root: FileNode,
    palette: [Color],
    maxDepth: Int = 4,
    maxChildrenPerNode: Int = 12,
    minVisibleFraction: Double = 0.012,
    maxArcCount: Int = 2_000,
    onPathActivated: ((String) -> Void)? = nil,
    pinnedArcID: String? = nil,
    onHoverSnapshotChanged: ((RadialBreakdownInspectorSnapshot?) -> Void)? = nil,
    onRootSnapshotReady: ((RadialBreakdownInspectorSnapshot?) -> Void)? = nil
  ) {
    let arcs = RadialBreakdownLayout.makeArcs(
      from: root,
      maxDepth: maxDepth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction,
      maxArcCount: maxArcCount
    )
    let nonRootArcs = arcs.filter { $0.depth > 0 }
    var groupedByDepth: [Int: [RadialBreakdownArc]] = [:]
    for arc in nonRootArcs {
      groupedByDepth[arc.depth, default: []].append(arc)
    }
    for key in groupedByDepth.keys {
      groupedByDepth[key]?.sort { lhs, rhs in
        lhs.startAngle < rhs.startAngle
      }
    }

    var groupedChildren: [String: [RadialBreakdownArc]] = [:]
    for arc in nonRootArcs {
      guard let parentID = arc.parentID else { continue }
      groupedChildren[parentID, default: []].append(arc)
    }
    for key in groupedChildren.keys {
      groupedChildren[key]?.sort { lhs, rhs in
        if lhs.sizeBytes != rhs.sizeBytes {
          return lhs.sizeBytes > rhs.sizeBytes
        }
        return lhs.label < rhs.label
      }
    }
    let resolvedPalette = palette.isEmpty ? Self.defaultPalette : palette
    var cachedBaseColors: [String: Color] = [:]
    for arc in nonRootArcs {
      cachedBaseColors[arc.id] = Self.makeBaseColor(for: arc, palette: resolvedPalette)
    }

    let safeRootSize = max(root.sizeBytes, 1)
    var cachedInspectorSnapshots: [String: RadialBreakdownInspectorSnapshot] = [:]
    cachedInspectorSnapshots.reserveCapacity(arcs.count)
    for arc in arcs {
      let children = groupedChildren[arc.id] ?? []
      let snapshotChildren: [RadialBreakdownInspectorChild]
      if children.isEmpty {
        snapshotChildren = [
          RadialBreakdownInspectorChild(
            id: "\(arc.id)-none",
            label: "No contained items",
            sizeBytes: nil,
            symbolName: "tray.fill",
            isMuted: true
          )
        ]
      } else {
        snapshotChildren = Array(children.prefix(Self.inspectorRowCapacity)).map { childArc in
          RadialBreakdownInspectorChild(
            id: childArc.id,
            label: Self.label(for: childArc),
            sizeBytes: childArc.sizeBytes,
            symbolName: Self.symbolName(for: childArc),
            isMuted: false
          )
        }
      }

      cachedInspectorSnapshots[arc.id] = RadialBreakdownInspectorSnapshot(
        id: arc.id,
        label: Self.label(for: arc),
        path: arc.path,
        sizeBytes: arc.sizeBytes,
        shareOfRoot: max(0, min(1, Double(arc.sizeBytes) / Double(safeRootSize))),
        symbolName: Self.symbolName(for: arc),
        isDirectory: arc.isDirectory,
        isAggregate: arc.isAggregate,
        children: snapshotChildren
      )
    }

    self.rootSizeBytes = root.sizeBytes
    self.rootArcID = arcs.first(where: { $0.depth == 0 })?.id ?? root.id
    self.nonRootArcs = nonRootArcs
    self.arcsByDepth = groupedByDepth
    self.arcsByID = Dictionary(uniqueKeysWithValues: arcs.map { ($0.id, $0) })
    self.parentIDsByID = Dictionary(uniqueKeysWithValues: arcs.map { ($0.id, $0.parentID) })
    self.childrenByParentID = groupedChildren
    self.baseColorByArcID = cachedBaseColors
    self.inspectorSnapshotByArcID = cachedInspectorSnapshots
    self.palette = resolvedPalette
    self.maxDepth = max(arcs.map(\.depth).max() ?? 1, 1)
    self.onPathActivated = onPathActivated
    self.pinnedArcID = pinnedArcID
    self.onHoverSnapshotChanged = onHoverSnapshotChanged
    self.onRootSnapshotReady = onRootSnapshotReady
  }

  public var body: some View {
    chartSurface
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipped()
      .onAppear {
        onRootSnapshotReady?(makeInspectorSnapshot(forArcID: rootArcID))
        onHoverSnapshotChanged?(nil)
      }
      .onChange(of: hoveredArcID) { _, newHoveredArcID in
        onHoverSnapshotChanged?(makeInspectorSnapshot(forArcID: newHoveredArcID))
      }
  }

  private var chartSurface: some View {
    GeometryReader { geometry in
      let metrics = chartMetrics(in: geometry.size)
      let selection = currentSelection
      let relatedArcIDs = relatedArcIDs(for: selection?.id)

      ZStack {
        Canvas { context, _ in
          for arc in nonRootArcs {
            drawArc(
              arc,
              using: metrics,
              activeArcID: selection?.id,
              relatedArcIDs: relatedArcIDs,
              context: &context
            )
          }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
          switch phase {
          case let .active(location):
            hoveredArcID = hitTest(at: location, metrics: metrics)?.id
          case .ended:
            hoveredArcID = nil
          }
        }
        .gesture(
          SpatialTapGesture()
            .onEnded { event in
              let hitArc = hitTest(at: event.location, metrics: metrics)
              if let path = hitArc?.path, !path.isEmpty {
                onPathActivated?(path)
              }
            }
        )

        totalBadge(using: metrics)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .clipped()
      .animation(.easeInOut(duration: 0.12), value: pinnedArcID)
    }
  }

  private var currentSelection: RadialBreakdownArc? {
    if let pinnedArcID, let pinned = arcsByID[pinnedArcID] {
      return pinned
    }
    if let hoveredArcID, let hovered = arcsByID[hoveredArcID] {
      return hovered
    }
    return nil
  }

  private func makeInspectorSnapshot(forArcID arcID: String?) -> RadialBreakdownInspectorSnapshot? {
    guard let arcID else {
      return nil
    }
    return inspectorSnapshotByArcID[arcID]
  }

  private func chartMetrics(in size: CGSize) -> ChartMetrics {
    let insetX = max(12, size.width * 0.04)
    let insetY = max(12, size.height * 0.04)
    let drawingRect = CGRect(
      x: insetX,
      y: insetY,
      width: max(size.width - (insetX * 2), 0),
      height: max(size.height - (insetY * 2), 0)
    )

    let diameter = max(0, min(drawingRect.width, drawingRect.height) - 2)
    let chartRadius = diameter / 2
    let center = CGPoint(x: drawingRect.midX, y: drawingRect.midY)
    let donutRadius = max(chartRadius * 0.25, 34)
    let ringBandWidth = max((chartRadius - donutRadius) / CGFloat(maxDepth), 5)

    return ChartMetrics(
      center: center,
      chartRadius: chartRadius,
      donutRadius: donutRadius,
      ringBandWidth: ringBandWidth,
      drawingRect: drawingRect
    )
  }

  private func hitTest(at point: CGPoint, metrics: ChartMetrics) -> RadialBreakdownArc? {
    guard metrics.drawingRect.contains(point) else { return nil }

    let dx = point.x - metrics.center.x
    let dy = point.y - metrics.center.y
    let radius = sqrt((dx * dx) + (dy * dy))
    guard radius > metrics.donutRadius else { return nil }
    guard radius <= metrics.chartRadius else { return nil }

    let angle = normalizedAngle(from: atan2(dy, dx))
    for depth in hitTestDepthCandidates(for: radius, metrics: metrics) {
      guard let depthArcs = arcsByDepth[depth] else { continue }
      guard let arc = arc(at: angle, in: depthArcs) else { continue }
      let ringBounds = metrics.ringBounds(for: arc.depth)
      guard radius >= ringBounds.inner, radius <= ringBounds.outer else { continue }
      return arc
    }

    return nil
  }

  private func drawArc(
    _ arc: RadialBreakdownArc,
    using metrics: ChartMetrics,
    activeArcID: String?,
    relatedArcIDs: Set<String>?,
    context: inout GraphicsContext
  ) {
    let ringBounds = metrics.ringBounds(for: arc.depth)
    let span = arc.endAngle - arc.startAngle
    guard span > 0.0001 else { return }

    let midRadius = (ringBounds.inner + ringBounds.outer) * 0.5
    let angularGap = min(Double(2.5 / max(midRadius, 1)), span * 0.18)
    let startAngle = arc.startAngle + (angularGap * 0.5)
    let endAngle = arc.endAngle - (angularGap * 0.5)
    guard endAngle > startAngle else { return }

    var path = Path()
    path.addArc(
      center: metrics.center,
      radius: ringBounds.outer,
      startAngle: .radians(startAngle),
      endAngle: .radians(endAngle),
      clockwise: false
    )
    path.addArc(
      center: metrics.center,
      radius: ringBounds.inner,
      startAngle: .radians(endAngle),
      endAngle: .radians(startAngle),
      clockwise: true
    )
    path.closeSubpath()

    let isSelected = activeArcID == arc.id
    context.fill(path, with: .color(color(for: arc, activeArcID: activeArcID, relatedArcIDs: relatedArcIDs)))
    context.stroke(
      path,
      with: .color(isSelected ? Color.white.opacity(0.93) : Color.white.opacity(0.2)),
      lineWidth: isSelected ? 1.35 : 0.65
    )
  }

  private func color(for arc: RadialBreakdownArc, activeArcID: String?, relatedArcIDs: Set<String>?) -> Color {
    let base = baseColorByArcID[arc.id] ?? Self.makeBaseColor(for: arc, palette: palette)
    let depthOpacity = max(0.62, 0.94 - (Double(max(arc.depth - 1, 0)) * 0.08))
    let opacity: Double

    if let activeArcID {
      if relatedArcIDs?.contains(arc.id) == true {
        opacity = arc.id == activeArcID ? min(depthOpacity + 0.08, 1) : depthOpacity
      } else {
        opacity = depthOpacity * 0.26
      }
    } else {
      opacity = depthOpacity
    }

    return base.opacity(opacity)
  }

  private static func makeBaseColor(for arc: RadialBreakdownArc, palette: [Color]) -> Color {
    if arc.isAggregate {
      return Color.gray
    }
    let stableIDHash = stableHash64(of: arc.id)
    let familyIndex = abs(arc.branchIndex) % palette.count
    let siblingOffset = Int(stableIDHash % 3)
    let depthOffset = max(arc.depth - 1, 0)
    let paletteIndex = (familyIndex + siblingOffset + depthOffset) % palette.count
    let base = palette[paletteIndex]
    let depthShift = min(Double(max(arc.depth - 1, 0)) * 0.035, 0.18)
    return base.opacity(1 - depthShift)
  }

  private static func stableHash64(of value: String) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    let prime: UInt64 = 1_099_511_628_211

    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }

    return hash
  }

  private func relatedArcIDs(for activeArcID: String?) -> Set<String>? {
    guard let activeArcID else { return nil }
    guard arcsByID[activeArcID] != nil else { return nil }

    var related: Set<String> = [activeArcID]

    var parentCursor = parentIDsByID[activeArcID] ?? nil
    while let parent = parentCursor {
      related.insert(parent)
      parentCursor = parentIDsByID[parent] ?? nil
    }

    var childStack: [RadialBreakdownArc] = childrenByParentID[activeArcID] ?? []
    while let child = childStack.popLast() {
      related.insert(child.id)
      if let grandchildren = childrenByParentID[child.id] {
        childStack.append(contentsOf: grandchildren)
      }
    }

    return related
  }

  private func hitTestDepthCandidates(for radius: CGFloat, metrics: ChartMetrics) -> [Int] {
    let bandWidth = max(metrics.ringBandWidth, 0.0001)
    let estimatedDepth = Int(floor((radius - metrics.donutRadius) / bandWidth)) + 1
    let candidates = [estimatedDepth, estimatedDepth + 1, estimatedDepth - 1]
    var ordered: [Int] = []
    ordered.reserveCapacity(3)

    for depth in candidates where depth >= 1 && depth <= maxDepth {
      if !ordered.contains(depth) {
        ordered.append(depth)
      }
    }
    return ordered
  }

  private func arc(at angle: Double, in arcs: [RadialBreakdownArc]) -> RadialBreakdownArc? {
    guard !arcs.isEmpty else { return nil }
    var low = 0
    var high = arcs.count - 1

    while low <= high {
      let mid = (low + high) / 2
      let arc = arcs[mid]
      if angle < arc.startAngle {
        high = mid - 1
      } else if angle > arc.endAngle {
        low = mid + 1
      } else {
        return arc
      }
    }

    return nil
  }

  @ViewBuilder
  private func totalBadge(using metrics: ChartMetrics) -> some View {
    let donutDiameter = min(metrics.donutRadius * 1.84, metrics.chartRadius * 1.4)
    let sizeParts = formattedSizeParts(for: rootSizeBytes)

    VStack(spacing: 4) {
      Text(sizeParts.value)
        .font(.system(size: 22, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)

      if let unit = sizeParts.unit {
        Text(unit)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.primary.opacity(0.76))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, 6)
    .frame(width: donutDiameter, height: donutDiameter)
    .background(.ultraThinMaterial, in: Circle())
    .overlay(
      Circle()
        .stroke(Color.white.opacity(0.2), lineWidth: 0.9)
    )
    .position(metrics.center)
    .allowsHitTesting(false)
  }

  private func formattedSizeParts(for bytes: Int64) -> (value: String, unit: String?) {
    let formatted = ByteFormatter.string(from: bytes).trimmingCharacters(in: .whitespacesAndNewlines)
    let pieces = formatted
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }

    guard pieces.count >= 2 else {
      return (value: formatted, unit: nil)
    }

    let unit = pieces.last ?? ""
    let value = pieces.dropLast().joined(separator: " ")
    return (value: value, unit: unit.isEmpty ? nil : unit)
  }

  private static func symbolName(for arc: RadialBreakdownArc) -> String {
    if arc.isAggregate {
      return "ellipsis.circle.fill"
    }
    if arc.isDirectory {
      return "folder.fill"
    }

    let pathExtension = URL(fileURLWithPath: arc.path ?? "").pathExtension.lowercased()
    switch pathExtension {
    case "zip", "gz", "bz2", "xz", "tar", "rar", "7z", "dmg", "pkg":
      return "archivebox.fill"
    case "jpg", "jpeg", "png", "gif", "webp", "svg", "tif", "tiff", "heic":
      return "photo.fill"
    case "mp4", "mov", "mkv", "avi", "webm", "m4v":
      return "film.fill"
    case "mp3", "wav", "aac", "flac", "m4a":
      return "music.note"
    case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "m", "mm", "sh", "zsh":
      return "chevron.left.forwardslash.chevron.right"
    case "md", "txt", "json", "yaml", "yml", "toml", "xml", "csv", "log":
      return "doc.text.fill"
    default:
      let fileName = URL(fileURLWithPath: arc.path ?? "").lastPathComponent.lowercased()
      if fileName.contains("lock") {
        return "lock.fill"
      }
      return "doc.fill"
    }
  }

  private static func label(for arc: RadialBreakdownArc) -> String {
    if arc.isAggregate {
      return "Smaller objects..."
    }
    if !arc.label.isEmpty {
      return arc.label
    }
    guard let path = arc.path else {
      return "Unknown"
    }
    let component = URL(fileURLWithPath: path).lastPathComponent
    return component.isEmpty ? path : component
  }

  private func normalizedAngle(from angle: Double) -> Double {
    var normalized = angle
    let minAngle = -Double.pi / 2
    let maxAngle = (3 * Double.pi) / 2

    while normalized < minAngle {
      normalized += 2 * Double.pi
    }
    while normalized > maxAngle {
      normalized -= 2 * Double.pi
    }
    return normalized
  }
}
