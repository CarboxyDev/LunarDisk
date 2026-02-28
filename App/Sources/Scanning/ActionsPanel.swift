import AppKit
import CoreScan
import SwiftUI

enum FileActionKind: String, Sendable {
  case reveal
  case open
  case copyPath
  case moveToTrash
}

enum FileActionOutcome: Equatable, Sendable {
  case success(message: String)
  case missing
  case permissionDenied
  case failed(message: String)

  var isSuccess: Bool {
    if case .success = self {
      return true
    }
    return false
  }

  var message: String {
    switch self {
    case let .success(message):
      return message
    case .missing:
      return "Item is no longer available."
    case .permissionDenied:
      return "Permission denied by macOS."
    case let .failed(message):
      return message
    }
  }
}

struct FileActionResult: Identifiable, Equatable, Sendable {
  let kind: FileActionKind
  let path: String
  let outcome: FileActionOutcome

  var id: String { "\(kind.rawValue)|\(path)" }
}

struct FileActionBatchReport: Equatable, Sendable {
  let kind: FileActionKind
  let attemptedCount: Int
  let successCount: Int
  let missingCount: Int
  let permissionDeniedCount: Int
  let failedCount: Int
  let processedBytes: Int64?
  let results: [FileActionResult]
  let timestamp: Date

  var hasFailures: Bool {
    missingCount > 0 || permissionDeniedCount > 0 || failedCount > 0
  }

  var summary: String {
    if hasFailures {
      return "\(successCount)/\(attemptedCount) succeeded"
    }
    return "Completed \(successCount) item\(successCount == 1 ? "" : "s")"
  }
}

enum FileActionService {
  static func reveal(path: String) -> FileActionResult {
    reveal(paths: [path]).results.first
      ?? FileActionResult(kind: .reveal, path: path, outcome: .failed(message: "Reveal operation returned no result."))
  }

  static func reveal(paths: [String]) -> FileActionBatchReport {
    let normalized = dedupedPaths(paths)
    var selectableURLs: [URL] = []
    var results: [FileActionResult] = []

    for path in normalized {
      if FileManager.default.fileExists(atPath: path) {
        selectableURLs.append(URL(fileURLWithPath: path))
        results.append(FileActionResult(kind: .reveal, path: path, outcome: .success(message: "Revealed in Finder.")))
      } else {
        results.append(FileActionResult(kind: .reveal, path: path, outcome: .missing))
      }
    }

    if !selectableURLs.isEmpty {
      NSWorkspace.shared.activateFileViewerSelecting(selectableURLs)
    }

    return summarize(kind: .reveal, results: results, processedBytes: nil)
  }

  static func open(path: String) -> FileActionResult {
    guard FileManager.default.fileExists(atPath: path) else {
      return FileActionResult(kind: .open, path: path, outcome: .missing)
    }

    let didOpen = NSWorkspace.shared.open(URL(fileURLWithPath: path))
    if didOpen {
      return FileActionResult(kind: .open, path: path, outcome: .success(message: "Opened item."))
    }

    return FileActionResult(
      kind: .open,
      path: path,
      outcome: .failed(message: "macOS could not open this item.")
    )
  }

  static func copyPath(path: String) -> FileActionResult {
    guard FileManager.default.fileExists(atPath: path) else {
      return FileActionResult(kind: .copyPath, path: path, outcome: .missing)
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let didSet = pasteboard.setString(path, forType: .string)

    if didSet {
      return FileActionResult(kind: .copyPath, path: path, outcome: .success(message: "Copied path."))
    }

    return FileActionResult(
      kind: .copyPath,
      path: path,
      outcome: .failed(message: "Could not write to clipboard.")
    )
  }

  static func moveToTrash(path: String, estimatedBytes: Int64? = nil) -> FileActionBatchReport {
    moveToTrash(items: [(path: path, estimatedBytes: estimatedBytes)])
  }

  static func report(for result: FileActionResult, processedBytes: Int64? = nil) -> FileActionBatchReport {
    summarize(kind: result.kind, results: [result], processedBytes: processedBytes)
  }

  static func moveToTrash(items: [(path: String, estimatedBytes: Int64?)]) -> FileActionBatchReport {
    let canonicalized = items.map { (path: URL(fileURLWithPath: $0.path).standardized.path, estimatedBytes: $0.estimatedBytes) }
    let normalized = dedupedPaths(canonicalized.map(\.path))
    let bytesByPath = Dictionary(canonicalized.map { ($0.path, $0.estimatedBytes ?? 0) }, uniquingKeysWith: { first, _ in first })

    var results: [FileActionResult] = []
    var processedBytes = Int64(0)

    for path in normalized {
      if isBlockedSystemPath(path) {
        results.append(FileActionResult(kind: .moveToTrash, path: path, outcome: .failed(message: "Refusing to trash system-critical path.")))
        continue
      }

      guard FileManager.default.fileExists(atPath: path) else {
        results.append(FileActionResult(kind: .moveToTrash, path: path, outcome: .missing))
        continue
      }

      let sourceURL = URL(fileURLWithPath: path)
      do {
        _ = try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
        processedBytes += bytesByPath[path] ?? 0
        results.append(FileActionResult(kind: .moveToTrash, path: path, outcome: .success(message: "Moved to Trash.")))
      } catch {
        results.append(FileActionResult(kind: .moveToTrash, path: path, outcome: classifyTrashFailure(error: error)))
      }
    }

    return summarize(kind: .moveToTrash, results: results, processedBytes: processedBytes)
  }

  private static let blockedPrefixes = [
    "/System", "/usr", "/bin", "/sbin",
    "/private/etc", "/private/var/db",
    "/Library/Keychains"
  ]

  private static func isBlockedSystemPath(_ path: String) -> Bool {
    for prefix in blockedPrefixes {
      if path == prefix || path.hasPrefix(prefix + "/") {
        return true
      }
    }
    return false
  }

  private static func summarize(
    kind: FileActionKind,
    results: [FileActionResult],
    processedBytes: Int64?
  ) -> FileActionBatchReport {
    FileActionBatchReport(
      kind: kind,
      attemptedCount: results.count,
      successCount: results.filter { $0.outcome.isSuccess }.count,
      missingCount: results.filter {
        if case .missing = $0.outcome {
          return true
        }
        return false
      }.count,
      permissionDeniedCount: results.filter {
        if case .permissionDenied = $0.outcome {
          return true
        }
        return false
      }.count,
      failedCount: results.filter {
        if case .failed = $0.outcome {
          return true
        }
        return false
      }.count,
      processedBytes: processedBytes,
      results: results,
      timestamp: Date()
    )
  }

  private static func classifyTrashFailure(error: Error) -> FileActionOutcome {
    if isPermissionDenied(error: error) {
      return .permissionDenied
    }

    return .failed(message: error.localizedDescription)
  }

  private static func isPermissionDenied(error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
      return true
    }
    if nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EACCES) || nsError.code == Int(EPERM)) {
      return true
    }
    return false
  }

  private static func dedupedPaths(_ input: [String]) -> [String] {
    var seen = Set<String>()
    var unique: [String] = []
    unique.reserveCapacity(input.count)

    for path in input where !path.isEmpty {
      if seen.insert(path).inserted {
        unique.append(path)
      }
    }

    // Sort shortest-first so ancestors come before descendants.
    let sorted = unique.sorted { $0.count < $1.count }
    var kept: [String] = []
    kept.reserveCapacity(sorted.count)

    for path in sorted {
      let isDescendant = kept.contains { ancestor in
        let prefix = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(prefix)
      }
      if !isDescendant {
        kept.append(path)
      }
    }

    return kept
  }
}

struct ScanActionsSnapshot: Sendable {
  enum Risk: Int, CaseIterable, Identifiable, Sendable {
    case safe
    case review
    case caution

    var id: Int { rawValue }

    var label: String {
      switch self {
      case .safe:
        return "SAFE"
      case .review:
        return "REVIEW"
      case .caution:
        return "CAUTION"
      }
    }
  }

  enum Confidence: Int, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low

    var id: Int { rawValue }
  }

  enum Source: Int, CaseIterable, Identifiable, Sendable {
    case cleanupRule
    case topLevel
    case hotspot

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .cleanupRule:
        return "Cleanup Rule"
      case .topLevel:
        return "Top-Level Item"
      case .hotspot:
        return "Nested Hotspot"
      }
    }

    var priority: Int {
      switch self {
      case .cleanupRule:
        return 3
      case .topLevel:
        return 2
      case .hotspot:
        return 1
      }
    }
  }

  struct Candidate: Identifiable, Hashable, Sendable {
    let node: FileNode
    let title: String
    let guidance: String
    let source: Source
    let risk: Risk
    let confidence: Confidence
    let shareOfScan: Double
    let estimatedReclaimBytes: Int64
    let depth: Int
    let isSystemSensitive: Bool

    var id: String { node.id }

    var displayName: String {
      if node.name.isEmpty {
        return node.path
      }
      return node.name
    }
  }

  let rootPath: String
  let totalScanBytes: Int64
  private(set) var candidates: [Candidate]
  private(set) var quickWins: [Candidate]
  private(set) var safeCount: Int
  private(set) var reviewCount: Int
  private(set) var cautionCount: Int
  private(set) var totalEstimatedReclaimBytes: Int64

  init(rootNode: FileNode) {
    rootPath = rootNode.path
    totalScanBytes = max(rootNode.sizeBytes, 1)
    candidates = Self.buildCandidates(rootNode: rootNode)
    quickWins = []
    safeCount = 0
    reviewCount = 0
    cautionCount = 0
    totalEstimatedReclaimBytes = 0
    recomputeDerivedValues()
  }

  func selectedCandidates(ids: Set<String>) -> [Candidate] {
    candidates.filter { ids.contains($0.id) }
  }

  func estimatedBytes(for candidateIDs: Set<String>) -> Int64 {
    let selected = candidates
      .filter { candidateIDs.contains($0.id) }
      .sorted(by: Self.selectionSort)

    var included: [Candidate] = []
    included.reserveCapacity(selected.count)

    for candidate in selected {
      let hasAncestor = included.contains { selectedCandidate in
        Self.isPath(candidate.node.path, descendantOf: selectedCandidate.node.path)
      }
      if !hasAncestor {
        included.append(candidate)
      }
    }

    return included.reduce(Int64(0)) { partial, candidate in
      partial + candidate.estimatedReclaimBytes
    }
  }

  mutating func removeCandidates(withPaths paths: Set<String>) {
    guard !paths.isEmpty else { return }

    candidates.removeAll { paths.contains($0.node.path) }
    recomputeDerivedValues()
  }

  private mutating func recomputeDerivedValues() {
    safeCount = candidates.filter { $0.risk == .safe }.count
    reviewCount = candidates.filter { $0.risk == .review }.count
    cautionCount = candidates.filter { $0.risk == .caution }.count

    totalEstimatedReclaimBytes = estimatedBytes(
      for: Set(candidates.map(\.id))
    )

    let sorted = candidates.sorted(by: Self.quickWinSort)
    let primaryQuickWins = sorted.filter {
      $0.risk != .caution &&
        $0.confidence != .low &&
        !$0.isSystemSensitive
    }

    if !primaryQuickWins.isEmpty {
      quickWins = Array(primaryQuickWins.prefix(5))
    } else {
      quickWins = Array(sorted.filter { $0.risk != .caution }.prefix(3))
    }
  }

  private static func buildCandidates(rootNode: FileNode) -> [Candidate] {
    let insights = ScanInsightsSnapshot(rootNode: rootNode)

    var candidateByPath: [String: Candidate] = [:]

    for cleanup in insights.cleanupCandidates {
      let candidate = Candidate(
        node: cleanup.node,
        title: cleanup.category,
        guidance: cleanup.guidance,
        source: .cleanupRule,
        risk: adjustedRisk(for: cleanup.node.path, fallback: cleanup.risk.actionsRisk),
        confidence: .high,
        shareOfScan: cleanup.share,
        estimatedReclaimBytes: cleanup.node.sizeBytes,
        depth: pathDepth(cleanup.node.path),
        isSystemSensitive: isSystemSensitive(path: cleanup.node.path)
      )
      mergeCandidate(candidate, into: &candidateByPath)
    }

    let minTopLevelBytes = max(Int64(64 * 1_024 * 1_024), rootNode.sizeBytes / 100)
    for entry in insights.topDirectChildren.prefix(12) {
      let node = entry.node
      let qualifies = node.sizeBytes >= minTopLevelBytes || entry.share >= 0.03
      if !qualifies { continue }

      let candidate = Candidate(
        node: node,
        title: node.isDirectory ? "Large Folder" : "Large File",
        guidance: node.isDirectory
          ? "Review inside first. Prefer deleting specific subitems instead of entire folders."
          : "Review before deletion. Consider moving this file to external/cloud storage.",
        source: .topLevel,
        risk: adjustedRisk(for: node.path, fallback: .review),
        confidence: .medium,
        shareOfScan: entry.share,
        estimatedReclaimBytes: node.sizeBytes,
        depth: 1,
        isSystemSensitive: isSystemSensitive(path: node.path)
      )
      mergeCandidate(candidate, into: &candidateByPath)
    }

    let minHotspotBytes = max(Int64(100 * 1_024 * 1_024), rootNode.sizeBytes / 150)
    for hotspot in insights.hotspots.prefix(10) {
      let node = hotspot.node
      let qualifies = node.sizeBytes >= minHotspotBytes || hotspot.share >= 0.02
      if !qualifies { continue }

      let candidate = Candidate(
        node: node,
        title: "Nested Hotspot",
        guidance: "Inspect this nested path in Finder and remove only items you recognize.",
        source: .hotspot,
        risk: adjustedRisk(for: node.path, fallback: .review),
        confidence: .medium,
        shareOfScan: hotspot.share,
        estimatedReclaimBytes: node.sizeBytes,
        depth: hotspot.depth,
        isSystemSensitive: isSystemSensitive(path: node.path)
      )
      mergeCandidate(candidate, into: &candidateByPath)
    }

    return candidateByPath.values
      .sorted { lhs, rhs in
        if lhs.risk.rawValue != rhs.risk.rawValue {
          return lhs.risk.rawValue < rhs.risk.rawValue
        }
        if lhs.estimatedReclaimBytes != rhs.estimatedReclaimBytes {
          return lhs.estimatedReclaimBytes > rhs.estimatedReclaimBytes
        }
        return lhs.node.path < rhs.node.path
      }
  }

  private static func mergeCandidate(_ candidate: Candidate, into map: inout [String: Candidate]) {
    if let existing = map[candidate.node.path] {
      if shouldReplace(existing: existing, incoming: candidate) {
        map[candidate.node.path] = candidate
      }
      return
    }

    map[candidate.node.path] = candidate
  }

  private static func shouldReplace(existing: Candidate, incoming: Candidate) -> Bool {
    if incoming.source.priority != existing.source.priority {
      return incoming.source.priority > existing.source.priority
    }
    if incoming.confidence.rawValue != existing.confidence.rawValue {
      return incoming.confidence.rawValue < existing.confidence.rawValue
    }
    if incoming.risk.rawValue != existing.risk.rawValue {
      return incoming.risk.rawValue < existing.risk.rawValue
    }
    return incoming.estimatedReclaimBytes > existing.estimatedReclaimBytes
  }

  private static func selectionSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.depth != rhs.depth {
      return lhs.depth < rhs.depth
    }
    if lhs.estimatedReclaimBytes != rhs.estimatedReclaimBytes {
      return lhs.estimatedReclaimBytes > rhs.estimatedReclaimBytes
    }
    return lhs.node.path < rhs.node.path
  }

  private static func quickWinSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.risk.rawValue != rhs.risk.rawValue {
      return lhs.risk.rawValue < rhs.risk.rawValue
    }
    if lhs.confidence.rawValue != rhs.confidence.rawValue {
      return lhs.confidence.rawValue < rhs.confidence.rawValue
    }
    if lhs.estimatedReclaimBytes != rhs.estimatedReclaimBytes {
      return lhs.estimatedReclaimBytes > rhs.estimatedReclaimBytes
    }
    return lhs.node.path < rhs.node.path
  }

  private static func adjustedRisk(for path: String, fallback: Risk) -> Risk {
    let lowercasedPath = path.lowercased()
    if isSystemSensitive(path: lowercasedPath) {
      return .caution
    }

    if pathMatchesToken(lowercasedPath, token: "/library/caches/") ||
      pathMatchesToken(lowercasedPath, token: "/.cache/") ||
      pathMatchesToken(lowercasedPath, token: "/library/developer/xcode/deriveddata/") {
      return .safe
    }

    if pathMatchesToken(lowercasedPath, token: "/downloads/") || pathMatchesToken(lowercasedPath, token: "/node_modules/") {
      return .review
    }

    return fallback
  }

  private static func isSystemSensitive(path: String) -> Bool {
    let lowercased = path.lowercased()
    return sensitivePathTokens.contains { token in
      pathMatchesToken(lowercased, token: token)
    }
  }

  private static let sensitivePathTokens = [
    "/system/",
    "/usr/",
    "/bin/",
    "/sbin/",
    "/private/etc/",
    "/private/var/db/",
    "/library/application support/",
    "/library/preferences/",
    "/library/keychains/"
  ]

  private static func pathDepth(_ path: String) -> Int {
    path.split(separator: "/").count
  }

  private static func pathMatchesToken(_ path: String, token: String) -> Bool {
    if path.contains(token) {
      return true
    }

    let normalizedToken = token.hasSuffix("/") ? String(token.dropLast()) : token
    return path.hasSuffix(normalizedToken)
  }

  private static func isPath(_ path: String, descendantOf ancestor: String) -> Bool {
    if path == ancestor {
      return true
    }
    let normalizedAncestor = ancestor.hasSuffix("/") ? ancestor : "\(ancestor)/"
    return path.hasPrefix(normalizedAncestor)
  }
}

private extension ScanInsightsSnapshot.CleanupRisk {
  var actionsRisk: ScanActionsSnapshot.Risk {
    switch self {
    case .safe:
      return .safe
    case .review:
      return .review
    case .careful:
      return .caution
    }
  }
}

private enum ActionRiskFilter: String, CaseIterable, Identifiable {
  case all
  case safe
  case review
  case caution

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      return "All"
    case .safe:
      return "Safe"
    case .review:
      return "Review"
    case .caution:
      return "Caution"
    }
  }
}

private struct TrashIntent: Identifiable {
  let id = UUID()
  let sourceLabel: String
  let candidates: [ScanActionsSnapshot.Candidate]
}

struct ActionsPanel: View {
  private enum Layout {
    static let pageSize = 6
    static let queueRowHeight: CGFloat = 98
    static let queueRowSpacing: CGFloat = 10
    static let selectionToolbarSlotHeight: CGFloat = 58
  }

  let rootNode: FileNode
  let warningMessage: String?
  let onRevealInFinder: (String) -> Void
  let onRescan: () -> Void
  let cacheKey: String
  let cachedSnapshot: ScanActionsSnapshot?
  let onSnapshotReady: (ScanActionsSnapshot) -> Void

  @State private var snapshot: ScanActionsSnapshot?
  @State private var snapshotTask: Task<Void, Never>?
  @State private var isComputingSnapshot = false
  @State private var selectedCandidateIDs: Set<String> = []
  @State private var riskFilter: ActionRiskFilter = .all
  @State private var queuePageIndex = 0
  @State private var trashIntent: TrashIntent?
  @State private var lastReport: FileActionBatchReport?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let warningMessage {
        partialWarningBanner(warningMessage)
      }

      if let snapshot {
        summarySection(snapshot)
        actionQueueSection(snapshot)

        if let lastReport {
          lastRunSection(lastReport)
        }
      } else {
        loadingSection
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .confirmationDialog(
      "Confirm Move to Trash",
      isPresented: trashConfirmationBinding,
      presenting: trashIntent
    ) { intent in
      Button(role: .destructive) {
        runTrash(intent)
        trashIntent = nil
      } label: {
        Text(
          intent.candidates.count == 1
            ? "Move Item to Trash"
            : "Move \(intent.candidates.count) Items to Trash"
        )
      }

      Button("Cancel", role: .cancel) {
        trashIntent = nil
      }
    } message: { intent in
      Text(trashConfirmationMessage(for: intent))
    }
    .dialogIcon(Image(nsImage: NSApplication.shared.applicationIconImage))
    .onAppear {
      hydrateOrRefreshSnapshot(force: false)
    }
    .onChange(of: cacheKey) { _, _ in
      hydrateOrRefreshSnapshot(force: true)
    }
    .onChange(of: riskFilter) { _, _ in
      queuePageIndex = 0
    }
    .onDisappear {
      snapshotTask?.cancel()
      snapshotTask = nil
    }
  }

  private var loadingSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ZStack {
          Circle()
            .fill(AppTheme.Colors.surfaceElevated.opacity(0.65))
            .frame(width: 28, height: 28)

          if isComputingSnapshot {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: "checklist")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(AppTheme.Colors.textSecondary)
          }
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("Preparing Actions")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)

          Text("Building safe, high-impact cleanup actions from this scan.")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }
      }

      HStack(spacing: 8) {
        loadingPill(width: 136)
        loadingPill(width: 108)
        loadingPill(width: 92)
      }
    }
    .lunarShimmer(active: isComputingSnapshot)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func loadingPill(width: CGFloat) -> some View {
    Capsule(style: .continuous)
      .fill(AppTheme.Colors.surfaceElevated.opacity(0.72))
      .overlay(
        Capsule(style: .continuous)
          .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
      )
      .frame(width: width, height: 26)
  }

  private func summarySection(_ snapshot: ScanActionsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Action Summary")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Spacer(minLength: 8)

        Text("Conservative estimates")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }

      HStack(spacing: 8) {
        summaryChip(systemImage: "arrow.down.circle.fill", text: ByteFormatter.string(from: snapshot.totalEstimatedReclaimBytes))
        summaryChip(systemImage: "checklist", text: "\(snapshot.candidates.count) actions")
        summaryChip(systemImage: "checkmark.shield.fill", text: "\(snapshot.safeCount) safe")
        summaryChip(systemImage: "exclamationmark.triangle.fill", text: "\(snapshot.cautionCount) caution")
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text("Items are suggestions, not auto-delete decisions. Review every target before moving it to Trash.")
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func summaryChip(systemImage: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
        .font(.system(size: 10, weight: .semibold))
      Text(text)
        .font(.system(size: 11, weight: .medium))
    }
    .foregroundStyle(AppTheme.Colors.textSecondary)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.58))
        .overlay(
          Capsule(style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
        )
    )
  }

  private func actionQueueSection(_ snapshot: ScanActionsSnapshot) -> some View {
    let visibleCandidates = filteredCandidates(from: snapshot)
    let selected = snapshot.selectedCandidates(ids: selectedCandidateIDs)
    let selectedBytes = snapshot.estimatedBytes(for: selectedCandidateIDs)
    let quickWinIDs = Set(snapshot.quickWins.map(\.id))
    let safePageIndex = clampedPageIndex(totalCount: visibleCandidates.count)
    let pageItems = pagedCandidates(from: visibleCandidates, pageIndex: safePageIndex)
    let pageCount = totalPageCount(totalCount: visibleCandidates.count)

    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text("Action Queue")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Spacer(minLength: 8)

        Text("\(visibleCandidates.count) shown")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }

      HStack(spacing: 10) {
        LunarSegmentedControl(
          options: [
            LunarSegmentedControlOption(ActionRiskFilter.all.title, value: ActionRiskFilter.all),
            LunarSegmentedControlOption(ActionRiskFilter.safe.title, value: ActionRiskFilter.safe),
            LunarSegmentedControlOption(ActionRiskFilter.review.title, value: ActionRiskFilter.review),
            LunarSegmentedControlOption(ActionRiskFilter.caution.title, value: ActionRiskFilter.caution)
          ],
          selection: $riskFilter,
          minItemWidth: 70,
          horizontalPadding: 10,
          verticalPadding: 6
        )
      }

      if visibleCandidates.isEmpty {
        emptyQueueState
      } else {
        selectionToolbarSlot(
          selectedCount: selected.count,
          selectedBytes: selectedBytes,
          selectedCandidates: selected
        )

        VStack(alignment: .leading, spacing: 10) {
          ForEach(pageItems) { candidate in
            actionCandidateRow(
              candidate,
              showSelection: true,
              isQuickWin: quickWinIDs.contains(candidate.id)
            )
          }
        }
        .frame(
          maxWidth: .infinity,
          minHeight: queueViewportHeight,
          alignment: .topLeading
        )

        HStack(spacing: 10) {
          Button("Previous") {
            guard queuePageIndex > 0 else { return }
            queuePageIndex -= 1
          }
          .buttonStyle(LunarSecondaryButtonStyle())
          .disabled(queuePageIndex == 0)

          Spacer(minLength: 8)

          Button("Next") {
            guard queuePageIndex < pageCount - 1 else { return }
            queuePageIndex += 1
          }
          .buttonStyle(LunarSecondaryButtonStyle())
          .disabled(queuePageIndex >= pageCount - 1)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func selectionToolbarSlot(
    selectedCount: Int,
    selectedBytes: Int64,
    selectedCandidates: [ScanActionsSnapshot.Candidate]
  ) -> some View {
    Group {
      if selectedCandidates.isEmpty {
        Text("Select actions to enable bulk operations.")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .padding(.horizontal, 10)
          .padding(.vertical, 9)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(AppTheme.Colors.surfaceElevated.opacity(0.22))
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(AppTheme.Colors.cardBorder.opacity(0.7), lineWidth: 1)
              )
          )
      } else {
        integratedBatchToolbar(
          selectedCount: selectedCount,
          selectedBytes: selectedBytes,
          selectedCandidates: selectedCandidates
        )
      }
    }
    .frame(maxWidth: .infinity, minHeight: Layout.selectionToolbarSlotHeight, alignment: .topLeading)
  }

  private func integratedBatchToolbar(
    selectedCount: Int,
    selectedBytes: Int64,
    selectedCandidates: [ScanActionsSnapshot.Candidate]
  ) -> some View {
    HStack(spacing: 10) {
      summaryChip(systemImage: "checkmark.circle", text: "\(selectedCount) selected")
      summaryChip(systemImage: "arrow.down.circle", text: ByteFormatter.string(from: selectedBytes))

      Spacer(minLength: 8)

      Button {
        trashIntent = TrashIntent(sourceLabel: "Selection", candidates: selectedCandidates)
      } label: {
        Label("Move to Trash", systemImage: "trash.fill")
      }
      .buttonStyle(LunarDestructiveButtonStyle())

      Button("Clear") {
        selectedCandidateIDs.removeAll()
      }
      .buttonStyle(LunarSecondaryButtonStyle())
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.5))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
        )
    )
  }

  private func totalPageCount(totalCount: Int) -> Int {
    guard totalCount > 0 else { return 1 }
    let pageSize = Layout.pageSize
    return (totalCount + pageSize - 1) / pageSize
  }

  private var queueViewportHeight: CGFloat {
    CGFloat(Layout.pageSize) * Layout.queueRowHeight
      + CGFloat(Layout.pageSize - 1) * Layout.queueRowSpacing
  }

  private func clampedPageIndex(totalCount: Int) -> Int {
    let pageCount = totalPageCount(totalCount: totalCount)
    return min(max(queuePageIndex, 0), max(pageCount - 1, 0))
  }

  private func pageStartIndex(pageIndex: Int) -> Int {
    pageIndex * Layout.pageSize
  }

  private func pagedCandidates(
    from candidates: [ScanActionsSnapshot.Candidate],
    pageIndex: Int
  ) -> [ScanActionsSnapshot.Candidate] {
    guard !candidates.isEmpty else { return [] }

    let startIndex = pageStartIndex(pageIndex: pageIndex)
    guard startIndex < candidates.count else { return [] }

    let endIndex = min(startIndex + Layout.pageSize, candidates.count)
    return Array(candidates[startIndex ..< endIndex])
  }

  private func actionCandidateRow(
    _ candidate: ScanActionsSnapshot.Candidate,
    showSelection: Bool,
    isQuickWin: Bool
  ) -> some View {
    let isSelected = selectedCandidateIDs.contains(candidate.id)

    return HStack(alignment: .top, spacing: 10) {
      if showSelection {
        Button {
          toggleSelection(for: candidate)
        } label: {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Deselect" : "Select")
        .padding(.top, 2)
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(candidate.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)

          if isQuickWin {
            quickWinBadge
          }

          riskBadge(candidate.risk)

          Text(candidate.source.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
              Capsule(style: .continuous)
                .fill(AppTheme.Colors.surfaceElevated.opacity(0.65))
                .overlay(
                  Capsule(style: .continuous)
                    .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
                )
            )
        }

        Text(candidate.displayName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)

        Text(candidate.node.path)
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .lineLimit(1)

        Text(candidate.guidance)
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 6) {
        Text(ByteFormatter.string(from: candidate.estimatedReclaimBytes))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text(candidate.shareOfScan.formatted(.percent.precision(.fractionLength(0))))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textTertiary)

        HStack(spacing: 6) {
          compactActionButton("Reveal") {
            onRevealInFinder(candidate.node.path)
          }

          compactActionButton("Open") {
            handleSingleAction(FileActionService.open(path: candidate.node.path))
          }

          compactActionButton("Copy") {
            handleSingleAction(FileActionService.copyPath(path: candidate.node.path))
          }

          compactDestructiveActionButton("Trash") {
            trashIntent = TrashIntent(sourceLabel: "Single Item", candidates: [candidate])
          }
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.45))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
        )
    )
  }

  private var quickWinBadge: some View {
    Text("QUICK WIN")
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(AppTheme.Colors.statusSuccessForeground)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(AppTheme.Colors.statusSuccessBackground)
          .overlay(
            Capsule(style: .continuous)
              .stroke(AppTheme.Colors.statusSuccessBorder, lineWidth: 1)
          )
      )
  }

  private var emptyQueueState: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "line.3.horizontal.decrease.circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
        Text("No Actions Match This Filter")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }

      Text("Try broadening the filter to see all suggested cleanup actions.")
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      if riskFilter != .all {
        Button("Show All Actions") {
          riskFilter = .all
        }
        .buttonStyle(LunarSecondaryButtonStyle())
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.32))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
        )
    )
  }

  private func lastRunSection(_ report: FileActionBatchReport) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Last Action Run")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Spacer(minLength: 8)

        Text(report.summary)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }

      HStack(spacing: 8) {
        summaryChip(systemImage: "checkmark.circle", text: "\(report.successCount) success")
        summaryChip(systemImage: "xmark.circle", text: "\(report.failedCount) failed")
        summaryChip(systemImage: "slash.circle", text: "\(report.missingCount) missing")
      }

      if let processedBytes = report.processedBytes, report.kind == .moveToTrash, processedBytes > 0 {
        Text("Moved to Trash: \(ByteFormatter.string(from: processedBytes))")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }

      if report.hasFailures {
        VStack(alignment: .leading, spacing: 6) {
          Text("Failures")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)

          ForEach(report.results.filter { !$0.outcome.isSuccess }.prefix(4)) { result in
            Text("• \(result.path): \(result.outcome.message)")
              .font(.system(size: 11, weight: .regular))
              .foregroundStyle(AppTheme.Colors.textTertiary)
              .lineLimit(2)
          }
        }
      }

      Button("Rescan Now") {
        onRescan()
      }
      .buttonStyle(LunarPrimaryButtonStyle())
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func riskBadge(_ risk: ScanActionsSnapshot.Risk) -> some View {
    let style: (foreground: Color, background: Color, border: Color)

    switch risk {
    case .safe:
      style = (
        AppTheme.Colors.statusSuccessForeground,
        AppTheme.Colors.statusSuccessBackground,
        AppTheme.Colors.statusSuccessBorder
      )
    case .review:
      style = (
        AppTheme.Colors.chart1,
        AppTheme.Colors.chart1.opacity(0.16),
        AppTheme.Colors.chart1.opacity(0.42)
      )
    case .caution:
      style = (
        AppTheme.Colors.statusWarningForeground,
        AppTheme.Colors.statusWarningBackground,
        AppTheme.Colors.statusWarningBorder
      )
    }

    return Text(risk.label)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(style.foreground)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(style.background)
          .overlay(
            Capsule(style: .continuous)
              .stroke(style.border, lineWidth: 1)
          )
      )
  }

  private func compactActionButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(AppTheme.Colors.textPrimary)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(AppTheme.Colors.surfaceElevated.opacity(0.65))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
          )
      )
      .buttonStyle(.plain)
  }

  private func compactDestructiveActionButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: "trash.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.destructiveForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppTheme.Colors.destructive.opacity(0.9))
        )
    }
    .buttonStyle(.plain)
  }

  private func partialWarningBanner(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 12, weight: .semibold))
        Text("Partial Scan")
          .font(.system(size: 13, weight: .semibold))
      }
      .foregroundStyle(AppTheme.Colors.statusWarningForeground)

      Text(message)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Text("Some items were skipped, so recommended actions may miss hidden usage.")
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(AppTheme.Colors.statusWarningBackground.opacity(0.45))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.Colors.statusWarningBorder, lineWidth: 1)
        )
    )
  }

  private var trashConfirmationBinding: Binding<Bool> {
    Binding(
      get: { trashIntent != nil },
      set: { shouldPresent in
        if !shouldPresent {
          trashIntent = nil
        }
      }
    )
  }

  private func trashConfirmationMessage(for intent: TrashIntent) -> String {
    let candidateIDs = Set(intent.candidates.map(\.id))
    let estimatedBytes: Int64

    if let snapshot {
      estimatedBytes = snapshot.estimatedBytes(for: candidateIDs)
    } else {
      estimatedBytes = intent.candidates.reduce(Int64(0)) { partial, candidate in
        partial + candidate.estimatedReclaimBytes
      }
    }

    let cautionCount = intent.candidates.filter { $0.risk == .caution }.count
    var parts: [String] = [
      "\(intent.sourceLabel): \(intent.candidates.count) item\(intent.candidates.count == 1 ? "" : "s").",
      "Estimated reclaim: \(ByteFormatter.string(from: estimatedBytes))."
    ]

    if cautionCount > 0 {
      parts.append("Includes \(cautionCount) caution item\(cautionCount == 1 ? "" : "s").")
    }

    parts.append("Review before proceeding.")
    return parts.joined(separator: " ")
  }

  private func hydrateOrRefreshSnapshot(force: Bool) {
    if let cachedSnapshot {
      snapshot = cachedSnapshot
      isComputingSnapshot = false
      return
    }
    refreshSnapshotIfNeeded(force: force)
  }

  private func refreshSnapshotIfNeeded(force: Bool) {
    if !force, snapshot != nil {
      return
    }

    let rootSnapshot = rootNode
    let expectedKey = cacheKey

    snapshotTask?.cancel()
    isComputingSnapshot = true
    lastReport = nil
    selectedCandidateIDs.removeAll()
    queuePageIndex = 0

    snapshotTask = Task.detached(priority: .utility) {
      let computed = ScanActionsSnapshot(rootNode: rootSnapshot)
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard expectedKey == cacheKey else { return }
        snapshot = computed
        isComputingSnapshot = false
        onSnapshotReady(computed)
      }
    }
  }

  private func filteredCandidates(from snapshot: ScanActionsSnapshot) -> [ScanActionsSnapshot.Candidate] {
    let quickWinIDs = Set(snapshot.quickWins.map(\.id))
    let filtered = snapshot.candidates.filter { candidate in
      switch riskFilter {
      case .all:
        return true
      case .safe:
        return candidate.risk == .safe
      case .review:
        return candidate.risk == .review
      case .caution:
        return candidate.risk == .caution
      }
    }

    return filtered.sorted { lhs, rhs in
      let lhsQuickWin = quickWinIDs.contains(lhs.id)
      let rhsQuickWin = quickWinIDs.contains(rhs.id)

      if lhsQuickWin != rhsQuickWin {
        return lhsQuickWin
      }
      if lhs.estimatedReclaimBytes != rhs.estimatedReclaimBytes {
        return lhs.estimatedReclaimBytes > rhs.estimatedReclaimBytes
      }
      if lhs.risk.rawValue != rhs.risk.rawValue {
        return lhs.risk.rawValue < rhs.risk.rawValue
      }
      return lhs.node.path < rhs.node.path
    }
  }

  private func toggleSelection(for candidate: ScanActionsSnapshot.Candidate) {
    if selectedCandidateIDs.contains(candidate.id) {
      selectedCandidateIDs.remove(candidate.id)
    } else {
      selectedCandidateIDs.insert(candidate.id)
    }
  }

  private func handleSingleAction(_ result: FileActionResult) {
    lastReport = FileActionService.report(for: result)
  }

  private func runTrash(_ intent: TrashIntent) {
    let report = FileActionService.moveToTrash(
      items: intent.candidates.map {
        (path: $0.node.path, estimatedBytes: $0.estimatedReclaimBytes)
      }
    )
    handleBatchReport(report)

    let succeededPaths = Set(
      report.results.compactMap { result -> String? in
        guard result.outcome.isSuccess else { return nil }
        return result.path
      }
    )
    let succeededCandidateIDs = Set(
      intent.candidates.compactMap { candidate in
        succeededPaths.contains(candidate.node.path) ? candidate.id : nil
      }
    )

    if !succeededPaths.isEmpty, var snapshot {
      snapshot.removeCandidates(withPaths: succeededPaths)
      self.snapshot = snapshot
      onSnapshotReady(snapshot)
      selectedCandidateIDs.subtract(succeededCandidateIDs)
      queuePageIndex = clampedPageIndex(totalCount: filteredCandidates(from: snapshot).count)
    }
  }

  private func handleBatchReport(_ report: FileActionBatchReport) {
    lastReport = report
  }
}
