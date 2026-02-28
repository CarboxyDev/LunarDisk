import CoreGraphics
import CoreScan
import os
import QuartzCore
import SwiftUI

private let chartSignposter = OSSignposter(subsystem: "com.lunardisk.perf", category: "RadialChart")

private final class RadialBreakdownChartData {
  let rootSizeBytes: Int64
  let rootArcID: String
  let nonRootArcs: [RadialBreakdownArc]
  let arcsByDepth: [Int: [RadialBreakdownArc]]
  let arcsByID: [String: RadialBreakdownArc]
  let parentIDsByID: [String: String?]
  let childrenByParentID: [String: [RadialBreakdownArc]]
  let baseColorByArcID: [String: Color]
  let inspectorSnapshotByArcID: [String: RadialBreakdownInspectorSnapshot]
  let palette: [Color]
  let maxDepth: Int
  let majorArcIDsForHoverLift: Set<String>
  let interactionFidelity: RadialBreakdownChartView.InteractionFidelityConfig

  private static let inspectorRowCapacity = 6
  private static let majorLiftShareThreshold: Double = 0.02
  private static let majorLiftAngularSpanThreshold: Double = .pi / 14
  private static let majorLiftMaxDepth = 2

  init(
    root: FileNode,
    palette: [Color],
    maxDepth: Int,
    maxChildrenPerNode: Int,
    minVisibleFraction: Double,
    maxArcCount: Int,
    adaptiveFidelity: Bool
  ) {
    let chartInitState = chartSignposter.beginInterval("ChartData.init", "root=\(root.name)")

    let defaultPalette: [Color] = [
      Color(red: 78 / 255, green: 168 / 255, blue: 230 / 255),
      Color(red: 104 / 255, green: 205 / 255, blue: 176 / 255),
      Color(red: 214 / 255, green: 144 / 255, blue: 88 / 255),
      Color(red: 184 / 255, green: 129 / 255, blue: 203 / 255),
      Color(red: 195 / 255, green: 171 / 255, blue: 90 / 255),
    ]

    let requestedConfig = RadialBreakdownChartView.LayoutFidelityConfig(
      maxDepth: maxDepth,
      maxChildrenPerNode: maxChildrenPerNode,
      minVisibleFraction: minVisibleFraction,
      maxArcCount: maxArcCount
    )

    let layoutState = chartSignposter.beginInterval("ChartData.layout")
    var arcs = RadialBreakdownLayout.makeArcs(
      from: root,
      maxDepth: requestedConfig.maxDepth,
      maxChildrenPerNode: requestedConfig.maxChildrenPerNode,
      minVisibleFraction: requestedConfig.minVisibleFraction,
      maxArcCount: requestedConfig.maxArcCount
    )

    if adaptiveFidelity {
      let adaptedConfig = RadialBreakdownChartView.adaptedFidelityConfig(
        for: root,
        requested: requestedConfig,
        realizedArcCount: arcs.count
      )
      if adaptedConfig != requestedConfig {
        arcs = RadialBreakdownLayout.makeArcs(
          from: root,
          maxDepth: adaptedConfig.maxDepth,
          maxChildrenPerNode: adaptedConfig.maxChildrenPerNode,
          minVisibleFraction: adaptedConfig.minVisibleFraction,
          maxArcCount: adaptedConfig.maxArcCount
        )
      }
    }
    chartSignposter.endInterval("ChartData.layout", layoutState)

    let nonRootArcs = arcs.filter { $0.depth > 0 }
    let interactionFidelity = RadialBreakdownChartView.interactionFidelityConfig(forArcCount: nonRootArcs.count)
    var majorArcIDsForHoverLift: Set<String> = []
    if interactionFidelity.allowsMajorArcLift {
      let safeRootSize = Double(max(root.sizeBytes, 1))
      majorArcIDsForHoverLift = Set(
        nonRootArcs.compactMap { arc in
          guard !arc.isAggregate else { return nil }
          guard arc.depth <= Self.majorLiftMaxDepth else { return nil }
          let shareOfRoot = Double(max(arc.sizeBytes, 0)) / safeRootSize
          let angularSpan = arc.endAngle - arc.startAngle
          if shareOfRoot >= Self.majorLiftShareThreshold || angularSpan >= Self.majorLiftAngularSpanThreshold {
            return arc.id
          }
          return nil
        }
      )
    }

    let groupState = chartSignposter.beginInterval("ChartData.grouping")
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
    let resolvedPalette = palette.isEmpty ? defaultPalette : palette
    var cachedBaseColors: [String: Color] = [:]
    for arc in nonRootArcs {
      cachedBaseColors[arc.id] = RadialBreakdownChartView.makeBaseColor(for: arc, palette: resolvedPalette)
    }
    chartSignposter.endInterval("ChartData.grouping", groupState)

    let snapshotState = chartSignposter.beginInterval("ChartData.inspectorSnapshots")
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
            label: RadialBreakdownChartView.label(for: childArc),
            sizeBytes: childArc.sizeBytes,
            symbolName: RadialBreakdownChartView.symbolName(for: childArc),
            isMuted: false
          )
        }
      }

      cachedInspectorSnapshots[arc.id] = RadialBreakdownInspectorSnapshot(
        id: arc.id,
        label: RadialBreakdownChartView.label(for: arc),
        path: arc.path,
        sizeBytes: arc.sizeBytes,
        shareOfRoot: max(0, min(1, Double(arc.sizeBytes) / Double(safeRootSize))),
        symbolName: RadialBreakdownChartView.symbolName(for: arc),
        isDirectory: arc.isDirectory,
        isAggregate: arc.isAggregate,
        children: snapshotChildren
      )
    }

    chartSignposter.endInterval("ChartData.inspectorSnapshots", snapshotState)

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
    self.interactionFidelity = interactionFidelity
    self.majorArcIDsForHoverLift = majorArcIDsForHoverLift

    chartSignposter.emitEvent("ChartData.result", "\(arcs.count) arcs")
    chartSignposter.endInterval("ChartData.init", chartInitState)
  }
}

private final class ChartDataCache {
  var data: RadialBreakdownChartData?
  var key: String = ""
}

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

  fileprivate struct LayoutFidelityConfig: Equatable {
    let maxDepth: Int
    let maxChildrenPerNode: Int
    let minVisibleFraction: Double
    let maxArcCount: Int
  }

  fileprivate struct InteractionFidelityConfig {
    let hoverSamplingInterval: CFTimeInterval
    let hoverSnapshotDelayNanoseconds: UInt64
    let hoverClearDelayNanoseconds: UInt64
    let showsHoverOutline: Bool
    let allowsHoverAnimation: Bool
    let allowsMajorArcLift: Bool
  }

  private static let defaultPalette: [Color] = [
    Color(red: 78 / 255, green: 168 / 255, blue: 230 / 255),
    Color(red: 104 / 255, green: 205 / 255, blue: 176 / 255),
    Color(red: 214 / 255, green: 144 / 255, blue: 88 / 255),
    Color(red: 184 / 255, green: 129 / 255, blue: 203 / 255),
    Color(red: 195 / 255, green: 171 / 255, blue: 90 / 255),
  ]

  private let root: FileNode
  private let configPalette: [Color]
  private let configMaxDepth: Int
  private let configMaxChildrenPerNode: Int
  private let configMinVisibleFraction: Double
  private let configMaxArcCount: Int
  private let configAdaptiveFidelity: Bool
  private let onPathActivated: ((String) -> Void)?
  private let pinnedArcID: String?
  private let highlightedArcIDs: Set<String>?
  private let queuedArcIDs: Set<String>?
  private let onHoverSnapshotChanged: ((RadialBreakdownInspectorSnapshot?) -> Void)?
  private let onRootSnapshotReady: ((RadialBreakdownInspectorSnapshot?) -> Void)?

  @State private var chartCache = ChartDataCache()

  private var chartData: RadialBreakdownChartData {
    let cacheKey = "\(root.path)|\(root.sizeBytes)|\(root.children.count)"
    if let existing = chartCache.data, chartCache.key == cacheKey {
      return existing
    }
    let data = RadialBreakdownChartData(
      root: root,
      palette: configPalette,
      maxDepth: configMaxDepth,
      maxChildrenPerNode: configMaxChildrenPerNode,
      minVisibleFraction: configMinVisibleFraction,
      maxArcCount: configMaxArcCount,
      adaptiveFidelity: configAdaptiveFidelity
    )
    chartCache.data = data
    chartCache.key = cacheKey
    return data
  }

  @State private var hoveredArcID: String?
  @State private var renderedHoverArcID: String?
  @State private var hoverPresentationProgress: CGFloat = 0
  @State private var lastHoverUpdateTimestamp: CFTimeInterval = 0
  @State private var hoverSnapshotTask: Task<Void, Never>?
  @State private var hoverClearTask: Task<Void, Never>?
  @State private var hoverPresentationResetTask: Task<Void, Never>?
  @State private var hoverPresentationAnimationTask: Task<Void, Never>?
  @State private var entranceRevealClock: CGFloat = 0
  @State private var entranceAnimationTask: Task<Void, Never>?

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
    adaptiveFidelity: Bool = true,
    onPathActivated: ((String) -> Void)? = nil,
    pinnedArcID: String? = nil,
    highlightedArcIDs: Set<String>? = nil,
    queuedArcIDs: Set<String>? = nil,
    onHoverSnapshotChanged: ((RadialBreakdownInspectorSnapshot?) -> Void)? = nil,
    onRootSnapshotReady: ((RadialBreakdownInspectorSnapshot?) -> Void)? = nil
  ) {
    self.root = root
    self.configPalette = palette
    self.configMaxDepth = maxDepth
    self.configMaxChildrenPerNode = maxChildrenPerNode
    self.configMinVisibleFraction = minVisibleFraction
    self.configMaxArcCount = maxArcCount
    self.configAdaptiveFidelity = adaptiveFidelity
    self.onPathActivated = onPathActivated
    self.pinnedArcID = pinnedArcID
    self.highlightedArcIDs = highlightedArcIDs
    self.queuedArcIDs = queuedArcIDs
    self.onHoverSnapshotChanged = onHoverSnapshotChanged
    self.onRootSnapshotReady = onRootSnapshotReady
  }

  public var body: some View {
    chartSurface
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipped()
      .onAppear {
        onRootSnapshotReady?(makeInspectorSnapshot(forArcID: chartData.rootArcID))
        onHoverSnapshotChanged?(nil)
        performEntranceReveal()
      }
      .onChange(of: hoveredArcID) { oldHoveredArcID, newHoveredArcID in
        hoverSnapshotTask?.cancel()
        hoverClearTask?.cancel()
        hoverPresentationResetTask?.cancel()
        hoverPresentationAnimationTask?.cancel()

        if chartData.interactionFidelity.allowsHoverAnimation {
          switch (oldHoveredArcID, newHoveredArcID) {
          case (nil, let next?) where !next.isEmpty:
            renderedHoverArcID = next
            setHoverPresentationProgress(0.08)
            animateHoverPresentation(to: 1, duration: 0.22)
          case (let previous?, nil):
            renderedHoverArcID = previous
            animateHoverPresentation(to: 0, duration: 0.18)
            hoverPresentationResetTask = Task { @MainActor in
              try? await Task.sleep(nanoseconds: 200_000_000)
              guard !Task.isCancelled else { return }
              guard hoveredArcID == nil else { return }
              renderedHoverArcID = nil
            }
          case (_, let next?) where !next.isEmpty:
            renderedHoverArcID = next
            setHoverPresentationProgress(max(hoverPresentationProgress, 0.78))
            animateHoverPresentation(to: 1, duration: 0.12)
          default:
            renderedHoverArcID = nil
            setHoverPresentationProgress(0)
          }
        } else {
          renderedHoverArcID = newHoveredArcID
          setHoverPresentationProgress(newHoveredArcID == nil ? 0 : 1)
        }

        guard let newHoveredArcID else {
          onHoverSnapshotChanged?(nil)
          return
        }

        hoverSnapshotTask = Task { @MainActor in
          try? await Task.sleep(nanoseconds: chartData.interactionFidelity.hoverSnapshotDelayNanoseconds)
          guard !Task.isCancelled else { return }
          onHoverSnapshotChanged?(makeInspectorSnapshot(forArcID: newHoveredArcID))
        }
      }
      .onDisappear {
        hoverSnapshotTask?.cancel()
        hoverClearTask?.cancel()
        hoverPresentationResetTask?.cancel()
        hoverPresentationAnimationTask?.cancel()
        entranceAnimationTask?.cancel()
        hoverSnapshotTask = nil
        hoverClearTask = nil
        hoverPresentationResetTask = nil
        hoverPresentationAnimationTask = nil
        entranceAnimationTask = nil
        renderedHoverArcID = nil
        setHoverPresentationProgress(0)
        entranceRevealClock = 0
      }
  }

  private var chartSurface: some View {
    GeometryReader { geometry in
      let metrics = chartMetrics(in: geometry.size)
      let activePinnedArcID = pinnedArcID
      let relatedArcIDs = relatedArcIDs(for: activePinnedArcID)
      let activeHighlightedArcIDs = highlightedArcIDs
      let activeQueuedArcIDs = queuedArcIDs

      ZStack {
        Canvas { context, _ in
          for arc in chartData.nonRootArcs {
            let depthEntrance = entranceProgress(forDepth: arc.depth)
            guard depthEntrance > 0.001 else { continue }

            if depthEntrance < 0.999 {
              context.drawLayer { layerCtx in
                layerCtx.opacity = Double(depthEntrance)
                drawArc(
                  arc,
                  using: metrics,
                  activeArcID: activePinnedArcID,
                  hoveredArcID: renderedHoverArcID,
                  hoverPresentationProgress: hoverPresentationProgress,
                  relatedArcIDs: relatedArcIDs,
                  highlightedArcIDs: activeHighlightedArcIDs,
                  queuedArcIDs: activeQueuedArcIDs,
                  entranceProgress: depthEntrance,
                  context: &layerCtx
                )
              }
            } else {
              drawArc(
                arc,
                using: metrics,
                activeArcID: activePinnedArcID,
                hoveredArcID: renderedHoverArcID,
                hoverPresentationProgress: hoverPresentationProgress,
                relatedArcIDs: relatedArcIDs,
                highlightedArcIDs: activeHighlightedArcIDs,
                queuedArcIDs: activeQueuedArcIDs,
                entranceProgress: 1,
                context: &context
              )
            }
          }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
          switch phase {
          case let .active(location):
            let hitArcID = hitTest(at: location, metrics: metrics)?.id
            if let hitArcID {
              hoverClearTask?.cancel()
              hoverClearTask = nil
              guard hitArcID != hoveredArcID else { return }

              let now = CACurrentMediaTime()
              if now - lastHoverUpdateTimestamp < chartData.interactionFidelity.hoverSamplingInterval {
                return
              }

              hoveredArcID = hitArcID
              lastHoverUpdateTimestamp = now
            } else if hoveredArcID != nil, hoverClearTask == nil {
              hoverClearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: chartData.interactionFidelity.hoverClearDelayNanoseconds)
                guard !Task.isCancelled else { return }
                guard hoveredArcID != nil else { return }
                hoveredArcID = nil
                lastHoverUpdateTimestamp = CACurrentMediaTime()
                hoverClearTask = nil
              }
            }
          case .ended:
            hoverClearTask?.cancel()
            hoverClearTask = nil
            if hoveredArcID != nil {
              hoveredArcID = nil
              lastHoverUpdateTimestamp = CACurrentMediaTime()
            }
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

  private func makeInspectorSnapshot(forArcID arcID: String?) -> RadialBreakdownInspectorSnapshot? {
    guard let arcID else {
      return nil
    }
    return chartData.inspectorSnapshotByArcID[arcID]
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
    let ringBandWidth = max((chartRadius - donutRadius) / CGFloat(chartData.maxDepth), 5)

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
      guard let depthArcs = chartData.arcsByDepth[depth] else { continue }
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
    hoveredArcID: String?,
    hoverPresentationProgress: CGFloat,
    relatedArcIDs: Set<String>?,
    highlightedArcIDs: Set<String>?,
    queuedArcIDs: Set<String>?,
    entranceProgress: CGFloat = 1,
    context: inout GraphicsContext
  ) {
    let isSelected = activeArcID == arc.id
    let isHovered = hoveredArcID == arc.id
    let hoverProgress = min(max(hoverPresentationProgress, 0), 1)
    let usesStrongHoverPresentation = chartData.interactionFidelity.showsHoverOutline && isHovered && !isSelected
    let shouldLiftHoveredArc = usesStrongHoverPresentation && chartData.majorArcIDsForHoverLift.contains(arc.id)

    var ringBounds = metrics.ringBounds(for: arc.depth)
    if usesStrongHoverPresentation {
      var inner = ringBounds.inner - (1.8 * hoverProgress)
      var outer = ringBounds.outer + (3.8 * hoverProgress)

      if shouldLiftHoveredArc {
        let desiredLift = 2.8 * hoverProgress
        let maxLift = max(0, (metrics.chartRadius - 0.6) - outer)
        let appliedLift = min(desiredLift, maxLift)
        inner += appliedLift
        outer += appliedLift
      }

      ringBounds.inner = max(metrics.donutRadius + 0.6, inner)
      ringBounds.outer = min(metrics.chartRadius - 0.6, outer)
      ringBounds.outer = max(ringBounds.outer, ringBounds.inner + 0.8)
    }

    if entranceProgress < 1 {
      let targetInner = ringBounds.inner
      let targetOuter = ringBounds.outer
      let compressedInner = metrics.donutRadius + 2
      let compressedOuter = metrics.donutRadius + 4
      ringBounds.inner = compressedInner + (targetInner - compressedInner) * entranceProgress
      ringBounds.outer = compressedOuter + (targetOuter - compressedOuter) * entranceProgress
    }

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

    let isQueued = queuedArcIDs?.contains(arc.id) == true

    context.fill(
      path,
      with: .color(
        color(
          for: arc,
          activeArcID: activeArcID,
          relatedArcIDs: relatedArcIDs,
          highlightedArcIDs: highlightedArcIDs,
          queuedArcIDs: queuedArcIDs,
          hoveredArcID: hoveredArcID,
          hoverPresentationProgress: hoverProgress
        )
      )
    )

    if isQueued {
      context.stroke(
        path,
        with: .color(Color(red: 0.9, green: 0.3, blue: 0.25).opacity(0.6)),
        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
      )
    }

    if usesStrongHoverPresentation {
      let liftBoost: CGFloat = shouldLiftHoveredArc ? 1.2 : 1
      context.drawLayer { layer in
        layer.addFilter(
          .shadow(
            color: Color.white.opacity((0.4 * hoverProgress) * liftBoost),
            radius: (7 * hoverProgress) * liftBoost,
            x: 0,
            y: 0
          )
        )
        layer.stroke(path, with: .color(Color.white.opacity(0.94 * hoverProgress)), lineWidth: 2.1 * hoverProgress)
      }
    }

    let baseHoverStrokeOpacity = Color.white.opacity(0.72)
    let animatedHoverStrokeOpacity = Color.white.opacity(0.72 + (0.24 * hoverProgress))

    context.stroke(
      path,
      with: .color(
        isSelected
          ? Color.white.opacity(0.93)
          : (usesStrongHoverPresentation ? animatedHoverStrokeOpacity : (isHovered ? baseHoverStrokeOpacity : Color.white.opacity(0.2)))
      ),
      lineWidth: isSelected ? 1.35 : (usesStrongHoverPresentation ? (1.05 + (0.75 * hoverProgress)) : (isHovered ? 1.05 : 0.65))
    )
  }

  private func color(
    for arc: RadialBreakdownArc,
    activeArcID: String?,
    relatedArcIDs: Set<String>?,
    highlightedArcIDs: Set<String>?,
    queuedArcIDs: Set<String>?,
    hoveredArcID: String?,
    hoverPresentationProgress: CGFloat
  ) -> Color {
    let base = chartData.baseColorByArcID[arc.id] ?? Self.makeBaseColor(for: arc, palette: chartData.palette)
    let depthOpacity = max(0.62, 0.94 - (Double(max(arc.depth - 1, 0)) * 0.08))
    let opacity: Double
    let clampedHoverProgress = Double(min(max(hoverPresentationProgress, 0), 1))
    let isQueued = queuedArcIDs?.contains(arc.id) == true

    if let activeArcID {
      if relatedArcIDs?.contains(arc.id) == true {
        opacity = arc.id == activeArcID ? min(depthOpacity + 0.08, 1) : depthOpacity
      } else {
        opacity = depthOpacity * 0.26
      }
    } else if let highlightedArcIDs, !highlightedArcIDs.isEmpty {
      if highlightedArcIDs.contains(arc.id) {
        opacity = min(depthOpacity + 0.06, 1)
      } else {
        opacity = depthOpacity * 0.22
      }
    } else if let hoveredArcID {
      if arc.id == hoveredArcID {
        let targetOpacity = min(depthOpacity + 0.18, 1)
        opacity = depthOpacity + ((targetOpacity - depthOpacity) * clampedHoverProgress)
      } else {
        let targetOpacity = max(depthOpacity * 0.46, 0.2)
        opacity = depthOpacity + ((targetOpacity - depthOpacity) * clampedHoverProgress)
      }
    } else {
      opacity = depthOpacity
    }

    if isQueued {
      let queuedColor = Color(red: 0.85, green: 0.32, blue: 0.28)
      return queuedColor.opacity(opacity * 0.75)
    }

    return base.opacity(opacity)
  }

  fileprivate static func makeBaseColor(for arc: RadialBreakdownArc, palette: [Color]) -> Color {
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

  fileprivate static func adaptedFidelityConfig(
    for root: FileNode,
    requested: LayoutFidelityConfig,
    realizedArcCount: Int
  ) -> LayoutFidelityConfig {
    var adapted = requested
    let saturationRatio = Double(realizedArcCount) / Double(max(requested.maxArcCount, 1))
    let directChildrenCount = root.children.count

    if saturationRatio >= 0.92 || directChildrenCount >= 140 {
      adapted = LayoutFidelityConfig(
        maxDepth: adapted.maxDepth,
        maxChildrenPerNode: min(adapted.maxChildrenPerNode, 8),
        minVisibleFraction: max(adapted.minVisibleFraction, 0.022),
        maxArcCount: min(adapted.maxArcCount, 900)
      )
    }

    if saturationRatio >= 0.98 || directChildrenCount >= 260 {
      adapted = LayoutFidelityConfig(
        maxDepth: min(adapted.maxDepth, 3),
        maxChildrenPerNode: min(adapted.maxChildrenPerNode, 6),
        minVisibleFraction: max(adapted.minVisibleFraction, 0.034),
        maxArcCount: min(adapted.maxArcCount, 650)
      )
    }

    return adapted
  }

  fileprivate static func interactionFidelityConfig(forArcCount arcCount: Int) -> InteractionFidelityConfig {
    if arcCount >= 620 {
      return InteractionFidelityConfig(
        hoverSamplingInterval: 1.0 / 24.0,
        hoverSnapshotDelayNanoseconds: 55_000_000,
        hoverClearDelayNanoseconds: 72_000_000,
        showsHoverOutline: false,
        allowsHoverAnimation: false,
        allowsMajorArcLift: false
      )
    }

    if arcCount >= 420 {
      return InteractionFidelityConfig(
        hoverSamplingInterval: 1.0 / 32.0,
        hoverSnapshotDelayNanoseconds: 32_000_000,
        hoverClearDelayNanoseconds: 66_000_000,
        showsHoverOutline: true,
        allowsHoverAnimation: false,
        allowsMajorArcLift: false
      )
    }

    return InteractionFidelityConfig(
      hoverSamplingInterval: 1.0 / 45.0,
      hoverSnapshotDelayNanoseconds: 18_000_000,
      hoverClearDelayNanoseconds: 58_000_000,
      showsHoverOutline: true,
      allowsHoverAnimation: true,
      allowsMajorArcLift: true
    )
  }

  private func setHoverPresentationProgress(_ value: CGFloat) {
    hoverPresentationProgress = min(max(value, 0), 1)
  }

  // MARK: – Entrance reveal animation

  /// Per-depth entrance progress (0 = hidden, 1 = fully revealed).
  /// Outer rings lag behind inner rings, producing a ripple-from-center effect.
  private func entranceProgress(forDepth depth: Int) -> CGFloat {
    let offset = 0.3 + CGFloat(max(depth - 1, 0)) * 0.78
    let raw = (entranceRevealClock - offset) / 1.0
    let clamped = min(max(raw, 0), 1)
    return clamped * clamped * (3 - 2 * clamped) // smoothstep
  }

  /// Center total-badge entrance (leads the rings slightly).
  private func entranceBadgeProgress() -> CGFloat {
    let raw = entranceRevealClock / 0.55
    let clamped = min(max(raw, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
  }

  /// Drives `entranceRevealClock` from 0 → target over a short duration,
  /// causing rings to appear one-by-one from center outward.
  private func performEntranceReveal() {
    entranceAnimationTask?.cancel()
    entranceRevealClock = 0

    let maxDepth = max(chartData.maxDepth, 1)
    let targetClock = CGFloat(maxDepth) + 0.5
    let totalDuration = max(0.45, 0.1 + Double(maxDepth) * 0.11)

    entranceAnimationTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 50_000_000)
      guard !Task.isCancelled else { return }

      let startedAt = CACurrentMediaTime()
      while !Task.isCancelled {
        let elapsed = CACurrentMediaTime() - startedAt
        let rawProgress = min(elapsed / totalDuration, 1)
        entranceRevealClock = CGFloat(rawProgress) * targetClock
        if rawProgress >= 1 { break }
        try? await Task.sleep(nanoseconds: 14_000_000)
      }

      guard !Task.isCancelled else { return }
      entranceRevealClock = targetClock
      entranceAnimationTask = nil
    }
  }

  private func animateHoverPresentation(to target: CGFloat, duration: CFTimeInterval) {
    hoverPresentationAnimationTask?.cancel()
    let clampedTarget = min(max(target, 0), 1)
    let start = hoverPresentationProgress

    guard duration > 0.001 else {
      setHoverPresentationProgress(clampedTarget)
      return
    }

    hoverPresentationAnimationTask = Task { @MainActor in
      let startedAt = CACurrentMediaTime()
      while !Task.isCancelled {
        let elapsed = CACurrentMediaTime() - startedAt
        let rawProgress = min(max(elapsed / duration, 0), 1)
        let easedProgress = rawProgress * (2 - rawProgress)
        let current = start + ((clampedTarget - start) * CGFloat(easedProgress))
        setHoverPresentationProgress(current)
        if rawProgress >= 1 {
          break
        }
        try? await Task.sleep(nanoseconds: 16_000_000)
      }

      guard !Task.isCancelled else { return }
      setHoverPresentationProgress(clampedTarget)
      hoverPresentationAnimationTask = nil
    }
  }

  private func relatedArcIDs(for activeArcID: String?) -> Set<String>? {
    guard let activeArcID else { return nil }
    guard chartData.arcsByID[activeArcID] != nil else { return nil }

    var related: Set<String> = [activeArcID]

    var parentCursor = chartData.parentIDsByID[activeArcID] ?? nil
    while let parent = parentCursor {
      related.insert(parent)
      parentCursor = chartData.parentIDsByID[parent] ?? nil
    }

    var childStack: [RadialBreakdownArc] = chartData.childrenByParentID[activeArcID] ?? []
    while let child = childStack.popLast() {
      related.insert(child.id)
      if let grandchildren = chartData.childrenByParentID[child.id] {
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

    for depth in candidates where depth >= 1 && depth <= chartData.maxDepth {
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
    let sizeParts = formattedSizeParts(for: chartData.rootSizeBytes)

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
    .opacity(Double(entranceBadgeProgress()))
    .scaleEffect(0.78 + 0.22 * entranceBadgeProgress())
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

  fileprivate static func symbolName(for arc: RadialBreakdownArc) -> String {
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

  fileprivate static func label(for arc: RadialBreakdownArc) -> String {
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
