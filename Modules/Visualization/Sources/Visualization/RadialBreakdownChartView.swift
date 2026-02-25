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

  private struct InspectorRow: Identifiable {
    let id: String
    let label: String
    let sizeText: String
    let symbolName: String
    let isPlaceholder: Bool
    let isMuted: Bool
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
  private let arcs: [RadialBreakdownArc]
  private let arcsByID: [String: RadialBreakdownArc]
  private let parentIDsByID: [String: String?]
  private let childrenByParentID: [String: [RadialBreakdownArc]]
  private let palette: [Color]
  private let maxDepth: Int
  private let onPinnedPathChange: ((String?) -> Void)?

  @State private var hoveredArcID: String?
  @State private var pinnedArcID: String?

  public init(root: FileNode) {
    self.init(root: root, palette: Self.defaultPalette, onPinnedPathChange: nil)
  }

  public init(
    root: FileNode,
    palette: [Color],
    maxDepth: Int = 4,
    maxChildrenPerNode: Int = 12,
    minVisibleFraction: Double = 0.012,
    maxArcCount: Int = 2_000,
    onPinnedPathChange: ((String?) -> Void)? = nil
  ) {
    let arcs = RadialBreakdownLayout.makeArcs(
      from: root,
      maxDepth: maxDepth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction,
      maxArcCount: maxArcCount
    )

    var groupedChildren: [String: [RadialBreakdownArc]] = [:]
    for arc in arcs where arc.depth > 0 {
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

    self.rootSizeBytes = root.sizeBytes
    self.rootArcID = arcs.first(where: { $0.depth == 0 })?.id ?? root.id
    self.arcs = arcs
    self.arcsByID = Dictionary(uniqueKeysWithValues: arcs.map { ($0.id, $0) })
    self.parentIDsByID = Dictionary(uniqueKeysWithValues: arcs.map { ($0.id, $0.parentID) })
    self.childrenByParentID = groupedChildren
    self.palette = palette.isEmpty ? Self.defaultPalette : palette
    self.maxDepth = max(arcs.map(\.depth).max() ?? 1, 1)
    self.onPinnedPathChange = onPinnedPathChange
  }

  public var body: some View {
    GeometryReader { geometry in
      let isWide = geometry.size.width >= 820

      Group {
        if isWide {
          HStack(alignment: .top, spacing: 14) {
            chartSurface
              .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
              .fill(Color.white.opacity(0.08))
              .frame(width: 1)

            inspectorPanel
              .frame(width: min(380, geometry.size.width * 0.34), alignment: .topLeading)
          }
        } else {
          VStack(spacing: 12) {
            chartSurface
              .frame(maxWidth: .infinity)
              .frame(height: max(210, geometry.size.height * 0.6))

            Divider()
              .overlay(Color.white.opacity(0.08))

            inspectorPanel
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipped()
    }
    .clipped()
  }

  private var chartSurface: some View {
    GeometryReader { geometry in
      let metrics = chartMetrics(in: geometry.size)
      let selection = currentSelection

      ZStack {
        Canvas { context, _ in
          for arc in arcs where arc.depth > 0 {
            drawArc(
              arc,
              using: metrics,
              activeArcID: selection?.id,
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
              if pinnedArcID == hitArc?.id {
                pinnedArcID = nil
              } else {
                pinnedArcID = hitArc?.id
              }
            }
        )
        .onChange(of: pinnedArcID) { _, pinnedArcID in
          let path = pinnedArcID.flatMap { arcsByID[$0]?.path }
          onPinnedPathChange?(path)
        }

        totalBadge(using: metrics)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .clipped()
      .animation(.easeInOut(duration: 0.12), value: hoveredArcID)
      .animation(.easeInOut(duration: 0.16), value: pinnedArcID)
    }
  }

  private var inspectorPanel: some View {
    let inspectedArc = currentSelection ?? arcsByID[rootArcID]
    let rows = makeInspectorRows(for: inspectedArc)

    return VStack(alignment: .leading, spacing: 12) {
      Text("Details")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.82))

      selectionSummaryBlock(for: inspectedArc)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        )

      Divider()
        .overlay(Color.white.opacity(0.08))

      Text("Contains")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.82))

      VStack(spacing: 6) {
        ForEach(rows) { row in
          inspectorRow(row)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.top, 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func selectionSummaryBlock(for inspectedArc: RadialBreakdownArc?) -> some View {
    if let inspectedArc {
      let percentage = (Double(inspectedArc.sizeBytes) / Double(max(rootSizeBytes, 1))) * 100
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Circle()
            .fill(baseColor(for: inspectedArc))
            .frame(width: 8, height: 8)

          Text(label(for: inspectedArc))
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Text("\(ByteFormatter.string(from: inspectedArc.sizeBytes)) • \(String(format: "%.1f", percentage))%")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.primary.opacity(0.78))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text("No selection.")
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(Color.primary.opacity(0.72))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func makeInspectorRows(for inspectedArc: RadialBreakdownArc?) -> [InspectorRow] {
    guard let inspectedArc else {
      return placeholderRows(count: Self.inspectorRowCapacity)
    }

    let children = childrenByParentID[inspectedArc.id] ?? []
    if children.isEmpty {
      var rows: [InspectorRow] = [
        InspectorRow(
          id: "\(inspectedArc.id)-none",
          label: "No contained items",
          sizeText: "",
          symbolName: "tray.fill",
          isPlaceholder: false,
          isMuted: true
        )
      ]
      rows.append(contentsOf: placeholderRows(count: Self.inspectorRowCapacity - rows.count))
      return rows
    }

    var rows: [InspectorRow] = Array(children.prefix(Self.inspectorRowCapacity)).map { arc in
      InspectorRow(
        id: arc.id,
        label: label(for: arc),
        sizeText: ByteFormatter.string(from: arc.sizeBytes),
        symbolName: symbolName(for: arc),
        isPlaceholder: false,
        isMuted: false
      )
    }

    if rows.count < Self.inspectorRowCapacity {
      rows.append(contentsOf: placeholderRows(count: Self.inspectorRowCapacity - rows.count))
    }
    return rows
  }

  private func placeholderRows(count: Int) -> [InspectorRow] {
    guard count > 0 else { return [] }
    return (0..<count).map { index in
      InspectorRow(
        id: "placeholder-\(index)",
        label: "",
        sizeText: "",
        symbolName: "circle.fill",
        isPlaceholder: true,
        isMuted: true
      )
    }
  }

  private func inspectorRow(_ row: InspectorRow) -> some View {
    HStack(spacing: 10) {
      Image(systemName: row.symbolName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(row.isMuted ? 0.45 : 0.68))
        .frame(width: 14, alignment: .center)

      Text(row.label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.primary.opacity(row.isMuted ? 0.52 : 0.86))
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 8)

      Text(row.sizeText)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.72))
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minHeight: 30)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white.opacity(row.isPlaceholder ? 0 : 0.03))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.white.opacity(row.isPlaceholder ? 0 : 0.07), lineWidth: 0.8)
        )
    )
    .opacity(row.isPlaceholder ? 0 : 1)
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
    let candidates = arcs
      .filter { $0.depth > 0 }
      .sorted { lhs, rhs in
        if lhs.depth == rhs.depth {
          return lhs.span < rhs.span
        }
        return lhs.depth > rhs.depth
      }

    for arc in candidates {
      let ringBounds = metrics.ringBounds(for: arc.depth)
      guard radius >= ringBounds.inner, radius <= ringBounds.outer else { continue }
      guard angle >= arc.startAngle, angle <= arc.endAngle else { continue }
      return arc
    }
    return nil
  }

  private func drawArc(
    _ arc: RadialBreakdownArc,
    using metrics: ChartMetrics,
    activeArcID: String?,
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
    context.fill(path, with: .color(color(for: arc, activeArcID: activeArcID)))
    context.stroke(
      path,
      with: .color(isSelected ? Color.white.opacity(0.93) : Color.white.opacity(0.2)),
      lineWidth: isSelected ? 1.35 : 0.65
    )
  }

  private func color(for arc: RadialBreakdownArc, activeArcID: String?) -> Color {
    let base = baseColor(for: arc)
    let depthOpacity = max(0.62, 0.94 - (Double(max(arc.depth - 1, 0)) * 0.08))
    let opacity: Double

    if let activeArcID {
      if isRelated(arcID: arc.id, activeArcID: activeArcID) {
        opacity = arc.id == activeArcID ? min(depthOpacity + 0.08, 1) : depthOpacity
      } else {
        opacity = depthOpacity * 0.26
      }
    } else {
      opacity = depthOpacity
    }

    return base.opacity(opacity)
  }

  private func baseColor(for arc: RadialBreakdownArc) -> Color {
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

  private func stableHash64(of value: String) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    let prime: UInt64 = 1_099_511_628_211

    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }

    return hash
  }

  private func isRelated(arcID: String, activeArcID: String) -> Bool {
    arcID == activeArcID
      || isAncestor(candidateAncestorID: arcID, arcID: activeArcID)
      || isAncestor(candidateAncestorID: activeArcID, arcID: arcID)
  }

  private func isAncestor(candidateAncestorID: String, arcID: String) -> Bool {
    var cursor = parentIDsByID[arcID] ?? nil
    while let currentParent = cursor {
      if currentParent == candidateAncestorID {
        return true
      }
      cursor = parentIDsByID[currentParent] ?? nil
    }
    return false
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

  private func symbolName(for arc: RadialBreakdownArc) -> String {
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

  private func label(for arc: RadialBreakdownArc) -> String {
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
