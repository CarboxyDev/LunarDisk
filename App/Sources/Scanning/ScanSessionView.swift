import CoreScan
import LunardiskAI
import SwiftUI
import Visualization

struct ScanSessionView: View {
  private enum ResultsLayoutVariant: Hashable {
    case twoColumn
    case singleColumn
  }

  private enum SessionSection: String, CaseIterable, Identifiable {
    case overview
    case insights
    case actions

    var id: String { rawValue }

    var title: String {
      switch self {
      case .overview:
        return "Overview"
      case .insights:
        return "Insights"
      case .actions:
        return "Actions"
      }
    }

    var icon: String {
      switch self {
      case .overview:
        return "chart.pie"
      case .insights:
        return "lightbulb"
      case .actions:
        return "checkmark.circle"
      }
    }
  }

  private struct DistributionSectionHeightsPreferenceKey: PreferenceKey {
    static var defaultValue: [ResultsLayoutVariant: CGFloat] = [:]

    static func reduce(value: inout [ResultsLayoutVariant: CGFloat], nextValue: () -> [ResultsLayoutVariant: CGFloat]) {
      value.merge(nextValue()) { _, next in
        next
      }
    }
  }

  private enum BreakdownViewMode: String, CaseIterable, Identifiable {
    case treemap
    case radial

    var id: String { rawValue }
  }

  private enum OverviewSupplementalMode: String, CaseIterable, Identifiable {
    case details
    case topItems

    var id: String { rawValue }

    var title: String {
      switch self {
      case .details:
        return "Details"
      case .topItems:
        return "Top Items"
      }
    }
  }

  private enum SessionPhase {
    case idle
    case scanning
    case results(FileNode)
    case failure(AppModel.ScanFailure)
  }

  private enum RadialDrillTransitionDirection {
    case deeper
    case shallower
  }

  private enum Layout {
    static let sectionSpacing: CGFloat = 16
    static let sideColumnWidth: CGFloat = 420
    static let chartPreferredHeightSingleColumn: CGFloat = 360
    static let chartPreferredHeightTwoColumn: CGFloat = 320
    static let chartMinHeight: CGFloat = 260
    static let chartMaxHeight: CGFloat = 620
  }

  let selectedURL: URL?
  let rootNode: FileNode?
  let insights: [Insight]
  let isScanning: Bool
  let scanProgress: ScanProgress?
  let warningMessage: String?
  let failure: AppModel.ScanFailure?
  let canStartScan: Bool
  let onCancelScan: () -> Void
  let onRetryScan: () -> Void
  let onBackToSetup: () -> Void
  let onOpenFullDiskAccess: () -> Void
  let onRevealInFinder: (String) -> Void

  @State private var treemapDensity: TreemapDensity = .clean
  @State private var breakdownViewMode: BreakdownViewMode = .radial
  @State private var distributionSectionHeights: [ResultsLayoutVariant: CGFloat] = [:]
  @State private var selectedSection: SessionSection = .overview
  @State private var revealHeader = false
  @State private var revealBody = false
  @State private var cachedInsightsSnapshot: (key: String, snapshot: ScanInsightsSnapshot)?
  @State private var cachedActionsSnapshot: (key: String, snapshot: ScanActionsSnapshot)?
  @State private var radialDrillPathStack: [String] = []
  @State private var radialDrillTransitionDirection: RadialDrillTransitionDirection = .deeper
  @State private var overviewSupplementalMode: OverviewSupplementalMode = .details
  @State private var radialHoverSnapshot: RadialBreakdownInspectorSnapshot?
  @State private var radialRootSnapshot: RadialBreakdownInspectorSnapshot?
  @State private var radialPinnedSnapshot: RadialBreakdownInspectorSnapshot?
  @Namespace private var sectionTabSelectionNamespace

  private var phase: SessionPhase {
    if isScanning {
      return .scanning
    }
    if let rootNode {
      return .results(rootNode)
    }
    if let failure {
      return .failure(failure)
    }
    return .idle
  }

  private var phaseID: String {
    switch phase {
    case .idle:
      return "idle"
    case .scanning:
      return "scanning"
    case let .results(rootNode):
      return "results-\(rootNode.id)"
    case .failure:
      return "failure"
    }
  }

  private var sectionID: String {
    "\(phaseID)-\(selectedSection.rawValue)"
  }

  private var canInteractWithSessionTabs: Bool {
    !isScanning && rootNode != nil
  }

  private var radialDrillFocusTransition: AnyTransition {
    let insertionEdge: Edge = radialDrillTransitionDirection == .deeper ? .trailing : .leading
    let removalEdge: Edge = radialDrillTransitionDirection == .deeper ? .leading : .trailing
    return .asymmetric(
      insertion: .opacity.combined(with: .move(edge: insertionEdge)),
      removal: .opacity.combined(with: .move(edge: removalEdge))
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
      sessionHeader
        .opacity(revealHeader ? 1 : 0)
        .offset(y: revealHeader ? 0 : 12)

      sessionSectionPicker
        .opacity(revealBody ? 1 : 0)
        .offset(y: revealBody ? 0 : 10)

      Group {
        switch phase {
        case .idle:
          preparingPanel

        case .scanning:
          loadingState

        case let .results(rootNode):
          resultsPhaseContent(rootNode: rootNode)

        case let .failure(failure):
          failurePanel(failure)
        }
      }
      .id(sectionID)
      .transition(
        .asymmetric(
          insertion: .opacity.combined(with: .move(edge: .trailing)),
          removal: .opacity.combined(with: .move(edge: .leading))
        )
      )
      .opacity(revealBody ? 1 : 0)
      .offset(y: revealBody ? 0 : 10)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animation(.spring(response: 0.38, dampingFraction: 0.9), value: phaseID)
    .animation(.easeInOut(duration: 0.2), value: selectedSection)
    .animation(.spring(response: 0.34, dampingFraction: 0.9), value: radialDrillPathStack)
    .onAppear {
      animateEntranceIfNeeded()
    }
    .onChange(of: isScanning) { _, scanning in
      if scanning {
        selectedSection = .overview
        resetRadialDrill(for: nil)
      } else if let rootNode, radialDrillPathStack.isEmpty {
        resetRadialDrill(for: rootNode)
      }
    }
    .onChange(of: breakdownViewMode) { _, mode in
      overviewSupplementalMode = defaultSupplementalMode(for: mode)
    }
    .onChange(of: rootNode?.id) { _, newRootID in
      if newRootID == nil {
        selectedSection = .overview
      }
      resetRadialDrill(for: rootNode)
      cachedInsightsSnapshot = nil
      cachedActionsSnapshot = nil
    }
  }

  private var sessionHeader: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(sessionTitle)
            .font(AppTheme.Typography.heroTitle)
            .foregroundStyle(AppTheme.Colors.textPrimary)

          Text(sessionSubtitle)
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .lineLimit(1)
        }

        Spacer(minLength: 12)

        statusPill
      }

      HStack(spacing: 10) {
        Label(targetLabel, systemImage: "scope")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .lineLimit(1)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(
            Capsule(style: .continuous)
              .fill(AppTheme.Colors.statusIdleBackground)
              .overlay(
                Capsule(style: .continuous)
                  .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
              )
          )

        Spacer(minLength: 0)

        Button("New Scan") {
          onBackToSetup()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        if isScanning {
          Button("Cancel") {
            onCancelScan()
          }
          .buttonStyle(LunarDestructiveButtonStyle())
          .keyboardShortcut(.cancelAction)
        } else if canStartScan {
          Button(rootNode == nil ? "Retry Scan" : "Scan Again") {
            onRetryScan()
          }
          .buttonStyle(LunarPrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private var sessionSectionPicker: some View {
    HStack(spacing: 8) {
      ForEach(SessionSection.allCases) { section in
        sessionSectionButton(section)
      }
    }
    .opacity(canInteractWithSessionTabs ? 1 : 0.76)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func sessionSectionButton(_ section: SessionSection) -> some View {
    let isSelected = section == selectedSection

    return Button {
      guard canInteractWithSessionTabs else {
        return
      }
      withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
        selectedSection = section
      }
    } label: {
      Label(section.title, systemImage: section.icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isSelected ? AppTheme.Colors.accentForeground : AppTheme.Colors.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 86)
        .background {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
              isSelected
                ? AppTheme.Colors.accent
                : AppTheme.Colors.surfaceElevated.opacity(0.62)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                  isSelected
                    ? AppTheme.Colors.accent.opacity(0.85)
                    : AppTheme.Colors.cardBorder,
                  lineWidth: 1
                )
            )
            .matchedGeometryEffect(
              id: isSelected ? "session-section-selection" : section.rawValue,
              in: sectionTabSelectionNamespace
            )
        }
    }
    .buttonStyle(.plain)
    .disabled(!canInteractWithSessionTabs)
    .accessibilityLabel(section.title)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var sessionTitle: String {
    switch phase {
    case .idle:
      return "Prepare Scan Session"
    case .scanning:
      return "Scanning Storage"
    case .results:
      return "Scan Complete"
    case .failure:
      return "Scan Needs Attention"
    }
  }

  private var sessionSubtitle: String {
    switch phase {
    case .idle:
      return "Waiting for scan metadata to initialize."
    case .scanning:
      return "Reading metadata and calculating folder sizes locally on your Mac."
    case .results:
      return "Use overview, insights, and actions to move from diagnosis to cleanup."
    case .failure:
      return "Review the issue and rerun with adjusted permissions or a new target."
    }
  }

  private var targetLabel: String {
    guard let selectedURL else {
      return "No target selected"
    }
    if selectedURL.path == "/" {
      return "Target: Macintosh HD"
    }
    return "Target: \(selectedURL.path)"
  }

  private var statusPill: some View {
    let style = statusPillStyle

    return HStack(spacing: 6) {
      Image(systemName: style.icon)
        .font(.system(size: 11, weight: .semibold))
      Text(style.title)
        .font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(style.foreground)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
        .fill(style.background)
        .overlay(
          Capsule(style: .continuous)
            .stroke(style.border, lineWidth: 1)
        )
        .lunarShimmer(active: style.shouldShimmer)
    )
  }

  private var statusPillStyle: (
    title: String,
    icon: String,
    foreground: Color,
    background: Color,
    border: Color,
    shouldShimmer: Bool
  ) {
    if isScanning {
      return (
        title: "Scanning",
        icon: "waveform.path.ecg",
        foreground: AppTheme.Colors.textPrimary,
        background: AppTheme.Colors.statusScanningBackground,
        border: AppTheme.Colors.cardBorder,
        shouldShimmer: true
      )
    }

    if rootNode != nil, warningMessage != nil {
      return (
        title: "Partial Results",
        icon: "exclamationmark.triangle.fill",
        foreground: AppTheme.Colors.statusWarningForeground,
        background: AppTheme.Colors.statusWarningBackground,
        border: AppTheme.Colors.statusWarningBorder,
        shouldShimmer: false
      )
    }

    if rootNode != nil && failure == nil {
      return (
        title: "Complete",
        icon: "checkmark.seal.fill",
        foreground: AppTheme.Colors.statusSuccessForeground,
        background: AppTheme.Colors.statusSuccessBackground,
        border: AppTheme.Colors.statusSuccessBorder,
        shouldShimmer: false
      )
    }

    if failure != nil {
      return (
        title: "Needs Attention",
        icon: "exclamationmark.triangle.fill",
        foreground: AppTheme.Colors.statusWarningForeground,
        background: AppTheme.Colors.statusWarningBackground,
        border: AppTheme.Colors.statusWarningBorder,
        shouldShimmer: false
      )
    }

    return (
      title: "Preparing",
      icon: "clock.fill",
      foreground: AppTheme.Colors.textSecondary,
      background: AppTheme.Colors.statusIdleBackground,
      border: AppTheme.Colors.cardBorder,
      shouldShimmer: false
    )
  }

  private var preparingPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)

        Text("Initializing scan session…")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }

      Text("If this state persists, return to setup and restart with a target.")
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private var loadingState: some View {
    ScanningStatePanel(
      title: "Scanning Storage",
      message: "Reading metadata and calculating folder sizes locally on your Mac.",
      progress: scanProgress
    )
  }

  @ViewBuilder
  private func resultsPhaseContent(rootNode: FileNode) -> some View {
    switch selectedSection {
    case .overview:
      let focusedNode = focusedOverviewNode(in: rootNode)
      VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
        if let warningMessage {
          partialScanBanner(warningMessage)
        }
        resultsContent(rootNode: focusedNode, scanRootNode: rootNode)
          .id("overview-focus-\(focusedNode.path)")
          .transition(radialDrillFocusTransition)
      }

    case .insights:
      let cacheKey = insightsCacheKey(for: rootNode)
      InsightsPanel(
        rootNode: rootNode,
        warningMessage: warningMessage,
        onRevealInFinder: onRevealInFinder,
        cacheKey: cacheKey,
        cachedSnapshot: cachedInsightsSnapshot?.key == cacheKey ? cachedInsightsSnapshot?.snapshot : nil,
        onSnapshotReady: { snapshot in
          cachedInsightsSnapshot = (key: cacheKey, snapshot: snapshot)
        }
      )

    case .actions:
      let cacheKey = actionsCacheKey(for: rootNode)
      ActionsPanel(
        rootNode: rootNode,
        warningMessage: warningMessage,
        onRevealInFinder: onRevealInFinder,
        onRescan: onRetryScan,
        cacheKey: cacheKey,
        cachedSnapshot: cachedActionsSnapshot?.key == cacheKey ? cachedActionsSnapshot?.snapshot : nil,
        onSnapshotReady: { snapshot in
          cachedActionsSnapshot = (key: cacheKey, snapshot: snapshot)
        }
      )
    }
  }

  private func failurePanel(_ failure: AppModel.ScanFailure) -> some View {
    let copy = failureCopy(for: failure)

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: copy.icon)
          .font(.system(size: 14, weight: .semibold))

        Text(copy.title)
          .font(.system(size: 16, weight: .semibold))
      }
      .foregroundStyle(AppTheme.Colors.textPrimary)

      Text(copy.message)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        if copy.suggestPermissionRecovery {
          Button("Open Full Disk Access") {
            onOpenFullDiskAccess()
          }
          .buttonStyle(LunarSecondaryButtonStyle())
        }

        if canStartScan {
          Button("Retry Scan") {
            onRetryScan()
          }
          .buttonStyle(LunarPrimaryButtonStyle())
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
        .fill(AppTheme.Colors.failureBannerBackground)
        .overlay(
          RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
  }

  private func failureCopy(for failure: AppModel.ScanFailure) -> (icon: String, title: String, message: String, suggestPermissionRecovery: Bool) {
    switch failure {
    case let .permissionDenied(path):
      return (
        "hand.raised.fill",
        "Permission Needed",
        "macOS blocked access to \(path). Open Full Disk Access, turn on LunarDisk, then try again.",
        true
      )
    case let .notFound(path):
      return (
        "questionmark.folder.fill",
        "Target Not Found",
        "The selected path no longer exists: \(path). Choose a new target and scan again.",
        false
      )
    case let .unreadable(path, message):
      return (
        "exclamationmark.triangle.fill",
        "Scan Failed",
        "Couldn't read \(path): \(message)",
        false
      )
    case let .unknown(message):
      return (
        "exclamationmark.triangle.fill",
        "Scan Failed",
        message,
        false
      )
    }
  }

  private func partialScanBanner(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 14, weight: .semibold))
        Text("Partial Results")
          .font(.system(size: 15, weight: .semibold))
      }
      .foregroundStyle(AppTheme.Colors.statusWarningForeground)

      Text(message)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
        .fill(AppTheme.Colors.statusWarningBackground.opacity(0.45))
        .overlay(
          RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
            .stroke(AppTheme.Colors.statusWarningBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
  }

  private func resultsContent(rootNode: FileNode, scanRootNode: FileNode) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: Layout.sectionSpacing) {
        distributionSection(
          rootNode: rootNode,
          scanRootNode: scanRootNode,
          chartHeight: Layout.chartPreferredHeightTwoColumn,
          layoutVariant: .twoColumn
        )
        supplementalResultsSections(
          rootNode: rootNode,
          useFixedWidth: true,
          targetHeight: distributionSectionHeights[.twoColumn] ?? 0
        )
      }

      VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
        distributionSection(
          rootNode: rootNode,
          scanRootNode: scanRootNode,
          chartHeight: Layout.chartPreferredHeightSingleColumn,
          layoutVariant: .singleColumn
        )
        supplementalResultsSections(
          rootNode: rootNode,
          useFixedWidth: false,
          targetHeight: distributionSectionHeights[.singleColumn] ?? 0
        )
      }
    }
    .onPreferenceChange(DistributionSectionHeightsPreferenceKey.self) { heights in
      distributionSectionHeights.merge(heights) { _, next in
        next
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func distributionSection(
    rootNode: FileNode,
    scanRootNode: FileNode,
    chartHeight: CGFloat,
    layoutVariant: ResultsLayoutVariant
  ) -> some View {
    let clampedChartHeight = min(max(chartHeight, Layout.chartMinHeight), Layout.chartMaxHeight)
    let effectiveChartHeight = min(max(clampedChartHeight, 410), Layout.chartMaxHeight)

    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Text("Storage Breakdown")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Spacer()

        breakdownModeSelector
      }

      if breakdownViewMode == .treemap {
        HStack(spacing: 8) {
          Label(ByteFormatter.string(from: rootNode.sizeBytes), systemImage: "externaldrive.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
              Capsule(style: .continuous)
                .fill(AppTheme.Colors.surfaceElevated.opacity(0.62))
                .overlay(
                  Capsule(style: .continuous)
                    .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
                )
            )

          Spacer()

          treemapDensityControl
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if breakdownViewMode == .radial {
        radialDrillControls(scanRootNode: scanRootNode)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      ZStack {
        if breakdownViewMode == .treemap {
          TreemapChartView(
            root: rootNode,
            palette: AppTheme.Colors.chartPalette,
            density: treemapDensity
          )
          .id("treemap-\(treemapDensity.rawValue)")
          .transition(.opacity.combined(with: .scale(scale: 0.985)))
        } else {
          RadialBreakdownChartView(
            root: rootNode,
            palette: AppTheme.Colors.chartPalette,
            onPathActivated: { path in
              handleRadialPathActivation(path: path, scanRootNode: scanRootNode)
            },
            pinnedArcID: radialPinnedSnapshot?.id,
            onHoverSnapshotChanged: { snapshot in
              radialHoverSnapshot = snapshot
            },
            onRootSnapshotReady: { snapshot in
              radialRootSnapshot = snapshot
            }
          )
          .contextMenu {
            radialChartContextMenu
          }
          .id("radial-\(rootNode.path)")
          .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: effectiveChartHeight)
      .animation(.easeInOut(duration: 0.22), value: breakdownViewMode)
      .animation(.easeInOut(duration: 0.16), value: treemapDensity)
      .animation(.easeInOut(duration: 0.18), value: radialDrillPathStack)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(AppTheme.Colors.surfaceElevated.opacity(0.38))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(AppTheme.Colors.cardBorder.opacity(0.8), lineWidth: AppTheme.Metrics.cardBorderWidth)
          )
      )
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .lunarPanelBackground()
    .background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: DistributionSectionHeightsPreferenceKey.self,
          value: [layoutVariant: proxy.size.height]
        )
      }
    )
  }

  private var breakdownModeSelector: some View {
    LunarSegmentedControl(
      options: [
        LunarSegmentedControlOption("Radial", value: BreakdownViewMode.radial, systemImage: "chart.pie.fill"),
        LunarSegmentedControlOption("Treemap", value: BreakdownViewMode.treemap, systemImage: "square.grid.2x2.fill")
      ],
      selection: $breakdownViewMode,
      minItemWidth: 96
    )
    .frame(width: 248)
  }

  private var treemapDensityControl: some View {
    LunarSegmentedControl(
      options: [
        LunarSegmentedControlOption("Simple", value: TreemapDensity.clean),
        LunarSegmentedControlOption("Detailed", value: TreemapDensity.detailed)
      ],
      selection: $treemapDensity,
      minItemWidth: 68,
      horizontalPadding: 10,
      verticalPadding: 6
    )
    .frame(width: 182)
    .padding(.vertical, 2)
  }

  private func supplementalResultsSections(
    rootNode: FileNode,
    useFixedWidth: Bool,
    targetHeight: CGFloat
  ) -> some View {
    let sections = Group {
      if breakdownViewMode == .radial {
        radialSupplementalSections(rootNode: rootNode, targetHeight: targetHeight)
      } else {
        TopItemsPanel(
          rootNode: rootNode,
          onRevealInFinder: onRevealInFinder,
          targetHeight: targetHeight
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)

    return Group {
      if useFixedWidth {
        sections
          .frame(width: Layout.sideColumnWidth, alignment: .topLeading)
      } else {
        sections
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }

  private func radialSupplementalSections(rootNode: FileNode, targetHeight: CGFloat) -> some View {
    let adjustedHeight = targetHeight > 0 ? max(0, targetHeight - 44) : 0

    return VStack(alignment: .leading, spacing: 10) {
      overviewSupplementalModePicker

      Group {
        if overviewSupplementalMode == .details {
          RadialDetailsPanel(
            snapshot: selectedRadialDetailSnapshot,
            isPinned: radialPinnedSnapshot != nil,
            onClearPinnedSelection: {
              clearPinnedRadialSelection()
            },
            targetHeight: adjustedHeight
          )
        } else {
          TopItemsPanel(
            rootNode: rootNode,
            onRevealInFinder: onRevealInFinder,
            targetHeight: adjustedHeight
          )
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var overviewSupplementalModePicker: some View {
    LunarSegmentedControl(
      options: [
        LunarSegmentedControlOption(OverviewSupplementalMode.details.title, value: OverviewSupplementalMode.details),
        LunarSegmentedControlOption(OverviewSupplementalMode.topItems.title, value: OverviewSupplementalMode.topItems)
      ],
      selection: $overviewSupplementalMode,
      minItemWidth: 98
    )
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var radialChartContextMenu: some View {
    if let hoveredSnapshot = radialHoverSnapshot {
      let isAlreadyPinned = radialPinnedSnapshot?.id == hoveredSnapshot.id
      Button(isAlreadyPinned ? "Unpin \"\(hoveredSnapshot.label)\"" : "Pin \"\(hoveredSnapshot.label)\"") {
        if isAlreadyPinned {
          clearPinnedRadialSelection()
        } else {
          pinRadialSelection(hoveredSnapshot)
        }
      }
    } else {
      Button("Pin Hovered Item") {}
        .disabled(true)
    }

    if let pinnedSnapshot = radialPinnedSnapshot,
       radialHoverSnapshot?.id != pinnedSnapshot.id
    {
      Divider()
      Button("Unpin \"\(pinnedSnapshot.label)\"") {
        clearPinnedRadialSelection()
      }
    }
  }

  private func radialDrillControls(scanRootNode: FileNode) -> some View {
    let breadcrumbs = radialBreadcrumbs(in: scanRootNode)

    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Array(breadcrumbs.enumerated()), id: \.element.path) { index, node in
          breadcrumbChip(
            title: displayName(for: node),
            systemImage: index == 0 ? "scope" : nil,
            isCurrent: index == breadcrumbs.count - 1,
            action: {
              jumpToRadialBreadcrumb(path: node.path)
            }
          )

          if index < breadcrumbs.count - 1 {
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(AppTheme.Colors.textTertiary)
          }
        }
      }
      .padding(.vertical, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.easeInOut(duration: 0.18), value: radialDrillPathStack)
  }

  private func breadcrumbChip(
    title: String,
    systemImage: String?,
    isCurrent: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Group {
        if let systemImage {
          Label(title, systemImage: systemImage)
        } else {
          Text(title)
        }
      }
      .font(.system(size: 11, weight: isCurrent ? .semibold : .medium))
      .foregroundStyle(isCurrent ? AppTheme.Colors.accentForeground : AppTheme.Colors.textSecondary)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(
        Capsule(style: .continuous)
          .fill(isCurrent ? AppTheme.Colors.accent : AppTheme.Colors.surfaceElevated.opacity(0.62))
          .overlay(
            Capsule(style: .continuous)
              .stroke(
                isCurrent ? AppTheme.Colors.accent.opacity(0.85) : AppTheme.Colors.cardBorder,
                lineWidth: 1
              )
          )
      )
    }
    .buttonStyle(.plain)
    .disabled(isCurrent)
  }

  private var selectedRadialDetailSnapshot: RadialBreakdownInspectorSnapshot? {
    radialPinnedSnapshot ?? radialHoverSnapshot ?? radialRootSnapshot
  }

  private func defaultSupplementalMode(for viewMode: BreakdownViewMode) -> OverviewSupplementalMode {
    switch viewMode {
    case .radial:
      return .details
    case .treemap:
      return .topItems
    }
  }

  private func pinRadialSelection(_ snapshot: RadialBreakdownInspectorSnapshot) {
    radialPinnedSnapshot = snapshot
    overviewSupplementalMode = .details
  }

  private func clearPinnedRadialSelection() {
    radialPinnedSnapshot = nil
  }

  private func clearRadialInspectorSnapshots(clearPinned: Bool = true) {
    radialHoverSnapshot = nil
    radialRootSnapshot = nil
    if clearPinned {
      radialPinnedSnapshot = nil
    }
  }

  private func resetRadialDrill(for rootNode: FileNode?) {
    clearRadialInspectorSnapshots()
    overviewSupplementalMode = defaultSupplementalMode(for: breakdownViewMode)
    radialDrillTransitionDirection = .deeper
    if let rootNode {
      radialDrillPathStack = [rootNode.path]
    } else {
      radialDrillPathStack = []
    }
  }

  private func focusedOverviewNode(in scanRootNode: FileNode) -> FileNode {
    if let candidatePath = radialDrillPathStack.last,
       let candidateNode = node(at: candidatePath, in: scanRootNode)
    {
      return candidateNode
    }
    return scanRootNode
  }

  private func radialBreadcrumbs(in scanRootNode: FileNode) -> [FileNode] {
    guard !radialDrillPathStack.isEmpty else {
      return [scanRootNode]
    }

    let resolved = radialDrillPathStack.compactMap { path in
      node(at: path, in: scanRootNode)
    }

    if resolved.isEmpty {
      return [scanRootNode]
    }

    if resolved.first?.path != scanRootNode.path {
      return [scanRootNode] + resolved
    }

    return resolved
  }

  private func handleRadialPathActivation(path: String, scanRootNode: FileNode) {
    guard let chain = nodePathChain(to: path, in: scanRootNode),
          let targetNode = chain.last,
          targetNode.isDirectory
    else {
      return
    }

    let nextStack = chain.map(\.path)
    let currentStack = radialDrillPathStack.isEmpty ? [scanRootNode.path] : radialDrillPathStack
    guard nextStack != currentStack else { return }

    clearRadialInspectorSnapshots()
    radialDrillTransitionDirection = nextStack.count >= currentStack.count ? .deeper : .shallower
    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
      radialDrillPathStack = nextStack
    }
  }

  private func jumpToRadialBreadcrumb(path: String) {
    guard let index = radialDrillPathStack.firstIndex(of: path) else { return }
    clearRadialInspectorSnapshots()
    radialDrillTransitionDirection = .shallower
    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
      radialDrillPathStack = Array(radialDrillPathStack.prefix(index + 1))
    }
  }

  private func nodePathChain(to targetPath: String, in rootNode: FileNode) -> [FileNode]? {
    var stack: [(node: FileNode, chain: [FileNode])] = [(rootNode, [rootNode])]

    while let current = stack.popLast() {
      if current.node.path == targetPath {
        return current.chain
      }

      if current.node.isDirectory, !current.node.children.isEmpty {
        for child in current.node.children.reversed() {
          stack.append((child, current.chain + [child]))
        }
      }
    }
    return nil
  }

  private func node(at path: String, in rootNode: FileNode) -> FileNode? {
    if rootNode.path == path {
      return rootNode
    }

    var stack: [FileNode] = rootNode.children
    while let current = stack.popLast() {
      if current.path == path {
        return current
      }
      if current.isDirectory, !current.children.isEmpty {
        stack.append(contentsOf: current.children)
      }
    }
    return nil
  }

  private func displayName(for node: FileNode) -> String {
    if node.path == "/" {
      return "Macintosh HD"
    }
    if node.name.isEmpty {
      return node.path
    }
    return node.name
  }

  private func insightsCacheKey(for node: FileNode) -> String {
    "\(node.id)|\(node.sizeBytes)|\(node.children.count)"
  }

  private func actionsCacheKey(for node: FileNode) -> String {
    "\(node.id)|\(node.sizeBytes)|\(node.children.count)"
  }

  private func animateEntranceIfNeeded() {
    guard !revealHeader, !revealBody else { return }

    Task { @MainActor in
      revealHeader = true
      try? await Task.sleep(nanoseconds: 100_000_000)
      revealBody = true
    }
  }
}
