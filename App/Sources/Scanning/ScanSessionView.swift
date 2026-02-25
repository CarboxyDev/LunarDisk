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

  private enum SessionPhase {
    case idle
    case scanning
    case results(FileNode)
    case failure(AppModel.ScanFailure)
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
    .onAppear {
      animateEntranceIfNeeded()
    }
    .onChange(of: isScanning) { _, scanning in
      if scanning {
        selectedSection = .overview
      }
    }
    .onChange(of: rootNode?.id) { _, newRootID in
      if newRootID == nil {
        selectedSection = .overview
      }
      cachedInsightsSnapshot = nil
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
      steps: [
        "Finding files and folders",
        "Calculating folder sizes",
        "Building Top Items"
      ]
    )
  }

  @ViewBuilder
  private func resultsPhaseContent(rootNode: FileNode) -> some View {
    switch selectedSection {
    case .overview:
      VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
        if let warningMessage {
          partialScanBanner(warningMessage)
        }
        resultsContent(rootNode: rootNode)
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
      actionsPanel(rootNode: rootNode)
    }
  }

  private func actionsPanel(rootNode: FileNode) -> some View {
    let candidates = Array(rootNode.sortedChildrenBySize.prefix(5))

    return VStack(alignment: .leading, spacing: 12) {
      Text("Actions")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("Focused next moves based on biggest direct consumers. This section is intentionally lightweight and will evolve into guided cleanup workflows.")
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      if candidates.isEmpty {
        Text("No actionable items found for this target.")
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(candidates, id: \.id) { node in
            actionRow(for: node)
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .lunarPanelBackground()
  }

  private func actionRow(for node: FileNode) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(node.name.isEmpty ? node.path : node.name)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)

        Text(ByteFormatter.string(from: node.sizeBytes))
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }

      Spacer(minLength: 0)

      Button("Reveal in Finder") {
        onRevealInFinder(node.path)
      }
      .buttonStyle(LunarSecondaryButtonStyle())
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.62))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
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

  private func resultsContent(rootNode: FileNode) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: Layout.sectionSpacing) {
        distributionSection(
          rootNode: rootNode,
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
    chartHeight: CGFloat,
    layoutVariant: ResultsLayoutVariant
  ) -> some View {
    let clampedChartHeight = min(max(chartHeight, Layout.chartMinHeight), Layout.chartMaxHeight)
    let effectiveChartHeight = min(max(clampedChartHeight, 410), Layout.chartMaxHeight)

    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Storage Breakdown")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)
          Text("\(breakdownViewTitle) for \(displayName(for: rootNode))")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 8) {
          breakdownModeSelector

          Text(ByteFormatter.string(from: rootNode.sizeBytes))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)
        }
      }

      Text(breakdownHelperText)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
          if breakdownViewMode == .treemap {
            treemapDensityControl
              .transition(.opacity.combined(with: .move(edge: .trailing)))
          }
        }
      .animation(.easeInOut(duration: 0.2), value: breakdownViewMode)

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
            palette: AppTheme.Colors.chartPalette
          )
          .id("radial")
          .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: effectiveChartHeight)
      .animation(.easeInOut(duration: 0.22), value: breakdownViewMode)
      .animation(.easeInOut(duration: 0.16), value: treemapDensity)
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

  private var breakdownHelperText: String {
    switch breakdownViewMode {
    case .treemap:
      return treemapDensity == .clean
        ? "Simple mode shows the biggest areas first."
        : "Detailed mode shows more of the nested folder structure."
    case .radial:
      return "Radial mode shows hierarchy from the center outward. Hover or click slices to inspect nested folders."
    }
  }

  private var breakdownViewTitle: String {
    switch breakdownViewMode {
    case .treemap:
      return "Treemap"
    case .radial:
      return "Radial"
    }
  }

  private func supplementalResultsSections(
    rootNode: FileNode,
    useFixedWidth: Bool,
    targetHeight: CGFloat
  ) -> some View {
    let sections = TopItemsPanel(
      rootNode: rootNode,
      onRevealInFinder: onRevealInFinder,
      targetHeight: targetHeight
    )
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

  private func animateEntranceIfNeeded() {
    guard !revealHeader, !revealBody else { return }

    Task { @MainActor in
      revealHeader = true
      try? await Task.sleep(nanoseconds: 100_000_000)
      revealBody = true
    }
  }
}
