import CoreScan
import LunardiskAI
import Observation
import SwiftUI
import Visualization

/// Hover-specific state isolated from the main interaction state.
/// Only views that need hover data should read from this object,
/// preventing the parent `ScanSessionView.body` from re-evaluating on every hover event.
@Observable
private final class RadialHoverState {
  var hoverSnapshot: RadialBreakdownInspectorSnapshot?
  var rootSnapshot: RadialBreakdownInspectorSnapshot?
}

@Observable
private final class RadialInteractionState {
  var drillPathStack: [String] = []
  var pinnedSnapshot: RadialBreakdownInspectorSnapshot?
  var supplementalMode: ScanSessionView.OverviewSupplementalMode = .details

  func pinSelection(_ snapshot: RadialBreakdownInspectorSnapshot) {
    pinnedSnapshot = snapshot
    supplementalMode = .details
  }

  func clearPinnedSelection() {
    pinnedSnapshot = nil
  }

  func clearInspectorSnapshots(hoverState: RadialHoverState, clearPinned: Bool = true) {
    hoverState.hoverSnapshot = nil
    hoverState.rootSnapshot = nil
    if clearPinned {
      pinnedSnapshot = nil
    }
  }

  func resetDrill(for rootNode: FileNode?, hoverState: RadialHoverState) {
    clearInspectorSnapshots(hoverState: hoverState)
    supplementalMode = .details
    if let rootNode {
      drillPathStack = [rootNode.path]
    } else {
      drillPathStack = []
    }
  }
}

/// Wrapper that reads hover-dependent state in its own body,
/// so changes to `hoverSnapshot` / `rootSnapshot` only re-render this subtree.
private struct RadialDetailsPanelContainer: View {
  let radialState: RadialInteractionState
  let hoverState: RadialHoverState
  let targetHeight: CGFloat
  let onRevealInFinder: (String) -> Void

  private var selectedDetailSnapshot: RadialBreakdownInspectorSnapshot? {
    radialState.pinnedSnapshot ?? hoverState.hoverSnapshot ?? hoverState.rootSnapshot
  }

  var body: some View {
    RadialDetailsPanel(
      snapshot: selectedDetailSnapshot,
      isPinned: radialState.pinnedSnapshot != nil,
      onClearPinnedSelection: {
        radialState.clearPinnedSelection()
      },
      targetHeight: targetHeight,
      onRevealInFinder: onRevealInFinder
    )
  }
}

/// Wrapper that reads hover state for the context menu in its own observation scope.
private struct TrashToast: Identifiable, Equatable {
  let id = UUID()
  let message: String
  let isSuccess: Bool

  static func == (lhs: TrashToast, rhs: TrashToast) -> Bool {
    lhs.id == rhs.id
  }
}

private struct RadialContextMenuContent: View {
  let radialState: RadialInteractionState
  let hoverState: RadialHoverState
  let trashQueueState: TrashQueueState
  let onRevealInFinder: (String) -> Void

  var body: some View {
    if let hoveredSnapshot = hoverState.hoverSnapshot {
      if let path = hoveredSnapshot.path, !hoveredSnapshot.isAggregate {
        let isQueued = trashQueueState.contains(path: path)
        Button(isQueued ? "Remove from Trash Queue" : "Add to Trash Queue") {
          if isQueued {
            trashQueueState.remove(path: path)
          } else {
            trashQueueState.add(TrashQueueItem(snapshot: hoveredSnapshot))
          }
        }

        Button("Reveal in Finder") {
          onRevealInFinder(path)
        }

        Divider()
      }

      let isAlreadyPinned = radialState.pinnedSnapshot?.id == hoveredSnapshot.id
      Button(isAlreadyPinned ? "Unpin \"\(hoveredSnapshot.label)\"" : "Pin \"\(hoveredSnapshot.label)\"") {
        if isAlreadyPinned {
          radialState.clearPinnedSelection()
        } else {
          radialState.pinSelection(hoveredSnapshot)
        }
      }
    } else {
      Text("Hover over an item to see options")
    }

    if let pinnedSnapshot = radialState.pinnedSnapshot,
       hoverState.hoverSnapshot?.id != pinnedSnapshot.id
    {
      Divider()
      Button("Unpin \"\(pinnedSnapshot.label)\"") {
        radialState.clearPinnedSelection()
      }
    }
  }
}

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

  enum OverviewSupplementalMode: String, CaseIterable, Identifiable {
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

  private enum Layout {
    static let sectionSpacing: CGFloat = 16
    static let sideColumnWidth: CGFloat = 420
    static let chartPreferredHeightSingleColumn: CGFloat = 360
    static let chartPreferredHeightTwoColumn: CGFloat = 320
    static let chartMinHeight: CGFloat = 260
    static let chartMaxHeight: CGFloat = 620
    static let breadcrumbChipMaxWidth: CGFloat = 220
    static let targetBadgeMaxWidth: CGFloat = 540
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
  let previousSummary: ScanSummary?
  let onRevealInFinder: (String) -> Void
  let volumeCapacity: AppModel.VolumeCapacity?
  var onRootNodeUpdate: ((FileNode) -> Void)?

  @State private var distributionSectionHeights: [ResultsLayoutVariant: CGFloat] = [:]
  @State private var selectedSection: SessionSection = .overview
  @State private var revealHeader = false
  @State private var revealBody = false
  @State private var cachedInsightsSnapshot: (key: String, snapshot: ScanInsightsSnapshot)?
  @State private var cachedActionsSnapshot: (key: String, snapshot: ScanActionsSnapshot)?
  @State private var radialState = RadialInteractionState()
  @State private var hoverState = RadialHoverState()
  @State private var searchQuery = ""
  @State private var searchResult: FileNodeSearchResult?
  @State private var searchTask: Task<Void, Never>?
  @State private var isSearchFieldFocused = false
  @State private var trashQueueState = TrashQueueState()
  @State private var trashQueueTrashIntent: TrashQueueTrashIntent?
  @State private var lastTrashQueueReport: FileActionBatchReport?
  @State private var trashToast: TrashToast?
  @State private var sessionDeletedBytes: Int64 = 0
  @State private var sessionDeletedCount: Int = 0
  @FocusState private var searchFieldFocused: Bool
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

  private var activeSearchHighlightIDs: Set<String>? {
    guard !searchQuery.isEmpty, let searchResult, !searchResult.matchedPaths.isEmpty else {
      return nil
    }
    return searchResult.matchedPaths
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      TextField("Search files…", text: $searchQuery)
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .regular))
        .focused($searchFieldFocused)

      if !searchQuery.isEmpty {
        Button {
          clearSearch()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .frame(maxWidth: 220)
    .background(
      Capsule(style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.62))
        .overlay(
          Capsule(style: .continuous)
            .stroke(
              searchFieldFocused ? AppTheme.Colors.accent.opacity(0.6) : AppTheme.Colors.cardBorder,
              lineWidth: 1
            )
        )
    )
    .onChange(of: searchQuery) { _, newQuery in
      performDebouncedSearch(query: newQuery)
    }
  }

  private func performDebouncedSearch(query: String) {
    searchTask?.cancel()
    searchTask = nil

    guard !query.isEmpty, let rootNode else {
      searchResult = nil
      return
    }

    let snapshot = rootNode
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled else { return }

      let result = await Task.detached(priority: .utility) {
        FileNodeSearch.search(in: snapshot, query: query)
      }.value

      guard !Task.isCancelled else { return }
      searchResult = result
      searchTask = nil
    }
  }

  private func clearSearch() {
    searchQuery = ""
    searchTask?.cancel()
    searchTask = nil
    searchResult = nil
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
        radialState.resetDrill(for: nil, hoverState: hoverState)
        clearSearch()
        trashQueueState.clear()
        lastTrashQueueReport = nil
        sessionDeletedBytes = 0
        sessionDeletedCount = 0
      } else if let rootNode, radialState.drillPathStack.isEmpty {
        radialState.resetDrill(for: rootNode, hoverState: hoverState)
      }
    }
    .onChange(of: rootNode?.id) { _, newRootID in
      if newRootID == nil {
        selectedSection = .overview
      }
      radialState.resetDrill(for: rootNode, hoverState: hoverState)
      trashQueueState.clear()
      lastTrashQueueReport = nil
      clearSearch()
      cachedInsightsSnapshot = nil
      cachedActionsSnapshot = nil
    }
    .confirmationDialog(
      "Move to Trash",
      isPresented: Binding(
        get: { trashQueueTrashIntent != nil },
        set: { if !$0 { trashQueueTrashIntent = nil } }
      ),
      presenting: trashQueueTrashIntent
    ) { intent in
      Button("Move \(intent.actionableItems.count) Item\(intent.actionableItems.count == 1 ? "" : "s") to Trash", role: .destructive) {
        runTrashQueue(intent)
      }
      Button("Cancel", role: .cancel) {
        trashQueueTrashIntent = nil
      }
    } message: { intent in
      let actionable = intent.actionableItems.count
      let blocked = intent.blockedCount
      let bytes = ByteFormatter.string(from: intent.estimatedBytes)
      if blocked > 0 {
        Text("This will move \(actionable) item\(actionable == 1 ? "" : "s") (\(bytes)) to the Trash. \(blocked) system-protected item\(blocked == 1 ? "" : "s") will be skipped.")
      } else {
        Text("This will move \(actionable) item\(actionable == 1 ? "" : "s") (\(bytes)) to the Trash.")
      }
    }
    .overlay(alignment: .top) {
      if let toast = trashToast {
        trashToastView(toast)
          .transition(.move(edge: .top).combined(with: .opacity))
          .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
              withAnimation(.easeOut(duration: 0.25)) {
                if trashToast?.id == toast.id {
                  trashToast = nil
                }
              }
            }
          }
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: trashToast)
  }

  private func runTrashQueue(_ intent: TrashQueueTrashIntent) {
    let actionableItems = intent.actionableItems
    guard !actionableItems.isEmpty else {
      trashQueueTrashIntent = nil
      return
    }

    // Keep the original queued paths before canonicalization
    let originalQueuedPaths = Set(actionableItems.map(\.path))

    let items = actionableItems.map { (path: $0.path, estimatedBytes: $0.sizeBytes as Int64?) }
    let report = FileActionService.moveToTrash(items: items)
    lastTrashQueueReport = report

    // Paths from the report are canonicalized — collect the ones that are gone
    let canonicalGonePaths = Set(
      report.results
        .filter {
          switch $0.outcome {
          case .success, .missing: return true
          default: return false
          }
        }
        .map(\.path)
    )

    // Failed canonical paths
    let canonicalFailedPaths = Set(
      report.results
        .filter {
          switch $0.outcome {
          case .success, .missing: return false
          default: return true
          }
        }
        .map(\.path)
    )

    // Map original queued paths: if its canonical form succeeded/missing, it's gone
    var goneOriginalPaths = Set<String>()
    for originalPath in originalQueuedPaths {
      let canonical = URL(fileURLWithPath: originalPath).standardized.path
      if canonicalGonePaths.contains(canonical) {
        goneOriginalPaths.insert(originalPath)
      } else if !canonicalFailedPaths.contains(canonical) {
        // Was deduped (parent was deleted) — also gone
        let parentWasDeleted = canonicalGonePaths.contains { gonePath in
          let prefix = gonePath.hasSuffix("/") ? gonePath : gonePath + "/"
          return canonical.hasPrefix(prefix)
        }
        if parentWasDeleted {
          goneOriginalPaths.insert(originalPath)
        }
      }
    }

    // Remove from queue: gone items + any queued children of gone items
    var pathsToRemove = goneOriginalPaths
    for queuedPath in trashQueueState.queuedPaths {
      let isChildOfGone = goneOriginalPaths.contains { gonePath in
        let prefix = gonePath.hasSuffix("/") ? gonePath : gonePath + "/"
        return queuedPath.hasPrefix(prefix)
      }
      if isChildOfGone {
        pathsToRemove.insert(queuedPath)
      }
    }
    trashQueueState.removeSucceeded(paths: pathsToRemove)

    // Prune the file tree using the original paths (which match the tree)
    if let rootNode, !goneOriginalPaths.isEmpty {
      if let pruned = rootNode.pruning(paths: goneOriginalPaths) {
        onRootNodeUpdate?(pruned)
      }
    }

    // Track cumulative stats
    let deletedCount = goneOriginalPaths.count
    let processedBytes = report.processedBytes ?? 0
    let failedCount = actionableItems.count - deletedCount
    sessionDeletedBytes += processedBytes
    sessionDeletedCount += deletedCount

    // Show toast
    if failedCount == 0 {
      trashToast = TrashToast(
        message: "Moved \(deletedCount) item\(deletedCount == 1 ? "" : "s") to Trash (\(ByteFormatter.string(from: processedBytes)))",
        isSuccess: true
      )
    } else {
      trashToast = TrashToast(
        message: "\(deletedCount) moved to Trash, \(failedCount) failed",
        isSuccess: false
      )
    }

    trashQueueTrashIntent = nil
  }

  private func trashToastView(_ toast: TrashToast) -> some View {
    let color: Color = toast.isSuccess ? .green : .orange
    return HStack(spacing: 8) {
      Image(systemName: toast.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)

      Text(toast.message)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(AppTheme.Colors.surface)
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(color.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
    )
    .padding(.top, 8)
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
        targetBadge

        if let deltaBadge = deltaBadgeContent {
          deltaBadge
        }

        if let capacityBadge = volumeCapacityBadge {
          capacityBadge
        }

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

  @ViewBuilder
  private var deltaBadgeContent: (some View)? {
    if let rootNode, let previousSummary, !isScanning {
      let delta = rootNode.sizeBytes - previousSummary.totalSizeBytes
      if delta != 0 {
        let isIncrease = delta > 0
        let symbol = isIncrease ? "+" : "\u{2212}"
        let label = "\(symbol)\(ByteFormatter.string(from: abs(delta))) since last scan"
        let foreground = isIncrease
          ? AppTheme.Colors.statusWarningForeground
          : AppTheme.Colors.statusSuccessForeground
        let background = isIncrease
          ? AppTheme.Colors.statusWarningBackground
          : AppTheme.Colors.statusSuccessBackground
        let border = isIncrease
          ? AppTheme.Colors.statusWarningBorder
          : AppTheme.Colors.statusSuccessBorder

        HStack(spacing: 5) {
          Image(systemName: isIncrease ? "arrow.up.right" : "arrow.down.right")
            .font(.system(size: 10, weight: .bold))
          Text(label)
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
          Capsule(style: .continuous)
            .fill(background)
            .overlay(
              Capsule(style: .continuous)
                .stroke(border, lineWidth: 1)
            )
        )
      }
    }
  }

  @ViewBuilder
  private var volumeCapacityBadge: (some View)? {
    if let cap = volumeCapacity, !isScanning {
      let purgeableBytes = cap.purgeableBytes
      let totalLabel = ByteFormatter.string(from: cap.totalBytes)
      let purgeableLabel = ByteFormatter.string(from: purgeableBytes)
      let helpText = "Total volume: \(totalLabel) · Available: \(ByteFormatter.string(from: cap.availableBytes)) · Purgeable: \(purgeableLabel) (auto-managed by macOS)"

      HStack(spacing: 5) {
        Image(systemName: "internaldrive")
          .font(.system(size: 10, weight: .semibold))
        Text("\(totalLabel) disk\(purgeableBytes > 0 ? " · ~\(purgeableLabel) purgeable" : "")")
          .font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(AppTheme.Colors.textSecondary)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(
        Capsule(style: .continuous)
          .fill(AppTheme.Colors.statusIdleBackground)
          .overlay(
            Capsule(style: .continuous)
              .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
          )
      )
      .help(helpText)
    }
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

  private var targetDisplayPath: String {
    guard let selectedURL else {
      return "No target selected"
    }
    if selectedURL.path == "/" {
      return "Macintosh HD"
    }
    return selectedURL.path
  }

  private var targetBadgeHelpText: String {
    guard let selectedURL else {
      return "No target selected"
    }
    if selectedURL.path == "/" {
      return "Target: Macintosh HD (/)"
    }
    return "Target: \(selectedURL.path)"
  }

  private var targetBadge: some View {
    Label {
      Text("Target: \(targetDisplayPath)")
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: Layout.targetBadgeMaxWidth, alignment: .leading)
    } icon: {
      Image(systemName: "scope")
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(AppTheme.Colors.textSecondary)
    .fixedSize()
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
    .help(targetBadgeHelpText)
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
    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
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

      if !trashQueueState.isEmpty || sessionDeletedCount > 0 {
        TrashQueueTrayView(
          trashQueueState: trashQueueState,
          onReviewAndDelete: {
            trashQueueTrashIntent = trashQueueState.makeTrashIntent()
          },
          onRevealInFinder: onRevealInFinder,
          lastReport: lastTrashQueueReport,
          sessionDeletedBytes: sessionDeletedBytes,
          sessionDeletedCount: sessionDeletedCount
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.22), value: trashQueueState.isEmpty)
    .animation(.easeInOut(duration: 0.22), value: sessionDeletedCount)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background {
      Button("") {
        guard let pinned = radialState.pinnedSnapshot,
              let path = pinned.path,
              !pinned.isAggregate
        else { return }
        trashQueueState.toggle(TrashQueueItem(snapshot: pinned))
      }
      .keyboardShortcut(.delete, modifiers: .command)
      .frame(width: 0, height: 0)
      .opacity(0)
    }
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
      HStack(alignment: .center, spacing: 12) {
        Text("Storage Breakdown")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Spacer(minLength: 0)

        searchField
      }

      radialDrillControls(scanRootNode: scanRootNode)

      RadialBreakdownChartView(
        root: rootNode,
        palette: AppTheme.Colors.chartPalette,
        onPathActivated: { path in
          handleRadialPathActivation(path: path, scanRootNode: scanRootNode)
        },
        pinnedArcID: radialState.pinnedSnapshot?.id,
        highlightedArcIDs: activeSearchHighlightIDs,
        queuedArcIDs: trashQueueState.isEmpty ? nil : trashQueueState.queuedPaths,
        onHoverSnapshotChanged: { snapshot in
          hoverState.hoverSnapshot = snapshot
        },
        onRootSnapshotReady: { snapshot in
          hoverState.rootSnapshot = snapshot
        }
      )
      .contextMenu {
        RadialContextMenuContent(
          radialState: radialState,
          hoverState: hoverState,
          trashQueueState: trashQueueState,
          onRevealInFinder: onRevealInFinder
        )
      }
      .id("radial-\(rootNode.path)")
      .frame(maxWidth: .infinity)
      .frame(height: effectiveChartHeight)
      .animation(.easeInOut(duration: 0.18), value: radialState.drillPathStack)
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

  private func supplementalResultsSections(
    rootNode: FileNode,
    useFixedWidth: Bool,
    targetHeight: CGFloat
  ) -> some View {
    let sections = radialSupplementalSections(rootNode: rootNode, targetHeight: targetHeight)
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
    let hasActiveSearch = !searchQuery.isEmpty

    return VStack(alignment: .leading, spacing: 10) {
      if hasActiveSearch {
        SearchResultsPanel(
          result: searchResult,
          query: searchQuery,
          isSearching: searchTask != nil && searchResult == nil,
          onRevealInFinder: onRevealInFinder,
          targetHeight: adjustedHeight
        )
      } else {
        overviewSupplementalModePicker

        Group {
          if radialState.supplementalMode == .details {
            RadialDetailsPanelContainer(
              radialState: radialState,
              hoverState: hoverState,
              targetHeight: adjustedHeight,
              onRevealInFinder: onRevealInFinder
            )
          } else {
            TopItemsPanel(
              rootNode: rootNode,
              onRevealInFinder: onRevealInFinder,
              targetHeight: adjustedHeight,
              trashQueueState: trashQueueState
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }

  private var overviewSupplementalModePicker: some View {
    LunarSegmentedControl(
      options: [
        LunarSegmentedControlOption(OverviewSupplementalMode.details.title, value: OverviewSupplementalMode.details),
        LunarSegmentedControlOption(OverviewSupplementalMode.topItems.title, value: OverviewSupplementalMode.topItems)
      ],
      selection: Bindable(radialState).supplementalMode,
      minItemWidth: 98
    )
    .frame(maxWidth: .infinity, alignment: .leading)
  }


  private func radialDrillControls(scanRootNode: FileNode) -> some View {
    let breadcrumbs = radialBreadcrumbs(in: scanRootNode)

    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Array(breadcrumbs.enumerated()), id: \.element.path) { index, node in
          breadcrumbChip(
            title: displayName(for: node),
            helpText: node.path,
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
    .animation(.easeInOut(duration: 0.18), value: radialState.drillPathStack)
  }

  private func breadcrumbChip(
    title: String,
    helpText: String,
    systemImage: String?,
    isCurrent: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Group {
        if let systemImage {
          Label {
            Text(title)
              .lineLimit(1)
              .truncationMode(.middle)
          } icon: {
            Image(systemName: systemImage)
          }
        } else {
          Text(title)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .font(.system(size: 11, weight: isCurrent ? .semibold : .medium))
      .foregroundStyle(isCurrent ? AppTheme.Colors.accentForeground : AppTheme.Colors.textSecondary)
      .frame(maxWidth: Layout.breadcrumbChipMaxWidth, alignment: .leading)
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
    .help(helpText)
  }

  private func focusedOverviewNode(in scanRootNode: FileNode) -> FileNode {
    if let candidatePath = radialState.drillPathStack.last,
       let candidateNode = node(at: candidatePath, in: scanRootNode)
    {
      return candidateNode
    }
    return scanRootNode
  }

  private func radialBreadcrumbs(in scanRootNode: FileNode) -> [FileNode] {
    guard !radialState.drillPathStack.isEmpty else {
      return [scanRootNode]
    }

    let resolved = radialState.drillPathStack.compactMap { path in
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
    let currentStack = radialState.drillPathStack.isEmpty ? [scanRootNode.path] : radialState.drillPathStack
    guard nextStack != currentStack else { return }

    radialState.clearInspectorSnapshots(hoverState: hoverState)
    radialState.drillPathStack = nextStack
  }

  private func jumpToRadialBreadcrumb(path: String) {
    guard let index = radialState.drillPathStack.firstIndex(of: path) else { return }
    radialState.clearInspectorSnapshots(hoverState: hoverState)
    radialState.drillPathStack = Array(radialState.drillPathStack.prefix(index + 1))
  }

  private func nodePathChain(to targetPath: String, in rootNode: FileNode) -> [FileNode]? {
    if rootNode.path == targetPath {
      return [rootNode]
    }
    guard targetPath.hasPrefix(rootNode.path) else { return nil }

    var chain: [FileNode] = [rootNode]
    var current = rootNode

    while current.path != targetPath {
      guard let next = current.children.first(where: {
        $0.path == targetPath || targetPath.hasPrefix($0.path + "/") || targetPath.hasPrefix($0.path)
      }) else {
        return nil
      }
      chain.append(next)
      current = next
    }

    return chain
  }

  private func node(at path: String, in rootNode: FileNode) -> FileNode? {
    if rootNode.path == path {
      return rootNode
    }
    guard path.hasPrefix(rootNode.path) else { return nil }

    var current = rootNode
    while current.path != path {
      guard let next = current.children.first(where: {
        $0.path == path || path.hasPrefix($0.path + "/") || path.hasPrefix($0.path)
      }) else {
        return nil
      }
      current = next
    }
    return current
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
