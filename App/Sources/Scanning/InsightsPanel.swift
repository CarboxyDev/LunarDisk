import CoreScan
import SwiftUI

struct InsightsPanel: View {
  let rootNode: FileNode
  let warningMessage: String?
  let onRevealInFinder: (String) -> Void

  @State private var snapshot: ScanInsightsSnapshot?
  @State private var isComputingSnapshot = false
  @State private var snapshotTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let warningMessage {
        partialWarningBanner(warningMessage)
      }

      if let snapshot {
        compactSummarySection(snapshot)
        topContributorsSection(snapshot)

        if !snapshot.cleanupCandidates.isEmpty {
          cleanupCandidatesSection(snapshot)
        }

        if !snapshot.extensionStats.isEmpty {
          extensionMixSection(snapshot)
        }

        if !snapshot.hotspots.isEmpty {
          deepHotspotsSection(snapshot)
        }
      } else {
        loadingPanel
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onAppear {
      refreshSnapshotIfNeeded(force: false)
    }
    .onChange(of: snapshotKey) { _, _ in
      refreshSnapshotIfNeeded(force: true)
    }
    .onDisappear {
      snapshotTask?.cancel()
      snapshotTask = nil
    }
  }

  private var snapshotKey: String {
    "\(rootNode.id)|\(rootNode.sizeBytes)|\(rootNode.children.count)"
  }

  private func refreshSnapshotIfNeeded(force: Bool) {
    if !force, snapshot != nil {
      return
    }

    let rootSnapshot = rootNode
    let expectedKey = snapshotKey

    snapshotTask?.cancel()
    isComputingSnapshot = true

    snapshotTask = Task.detached(priority: .utility) {
      let computed = ScanInsightsSnapshot(rootNode: rootSnapshot)
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard expectedKey == snapshotKey else { return }
        snapshot = computed
        isComputingSnapshot = false
      }
    }
  }

  private var loadingPanel: some View {
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
            Image(systemName: "sparkles")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(AppTheme.Colors.textSecondary)
          }
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("Preparing Insights")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)

          Text("Analyzing folders, hotspots, and file type distribution.")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }
      }

      HStack(spacing: 8) {
        loadingPill(width: 120)
        loadingPill(width: 106)
        loadingPill(width: 96)
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

  private func compactSummarySection(_ snapshot: ScanInsightsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Session Snapshot")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      HStack(spacing: 8) {
        summaryChip(systemImage: "externaldrive.fill", text: ByteFormatter.string(from: snapshot.totalSizeBytes))
        summaryChip(systemImage: "folder.fill", text: "\(snapshot.directoryCount.formatted()) folders")
        summaryChip(systemImage: "doc.fill", text: "\(snapshot.fileCount.formatted()) files")
        summaryChip(systemImage: "arrow.down.right.and.arrow.up.left", text: "Depth \(snapshot.maxDepth)")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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

  private func topContributorsSection(_ snapshot: ScanInsightsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Top Contributors")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      if snapshot.topDirectChildren.isEmpty {
        Text("No direct contributors found in this target.")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(snapshot.topDirectChildren) { entry in
            contributorRow(entry)
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func contributorRow(_ entry: ScanInsightsSnapshot.RankedNode) -> some View {
    HStack(spacing: 10) {
      Image(systemName: entry.node.isDirectory ? "folder.fill" : "doc.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 2) {
        Text(displayName(for: entry.node))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)

        Text("\(ByteFormatter.string(from: entry.node.sizeBytes)) • \(percentString(entry.share))")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }

      Spacer(minLength: 8)

      compactActionButton("Reveal") {
        onRevealInFinder(entry.node.path)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
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

  private func cleanupCandidatesSection(_ snapshot: ScanInsightsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Cleanup Opportunities")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      VStack(alignment: .leading, spacing: 10) {
        ForEach(snapshot.cleanupCandidates) { candidate in
          cleanupCandidateRow(candidate)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func cleanupCandidateRow(_ candidate: ScanInsightsSnapshot.CleanupCandidate) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(candidate.category)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textPrimary)

          riskBadge(candidate.risk)
        }

        Text(displayName(for: candidate.node))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .lineLimit(1)

        Text(candidate.guidance)
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 5) {
        Text(ByteFormatter.string(from: candidate.node.sizeBytes))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text(percentString(candidate.share))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textTertiary)

        compactActionButton("Reveal") {
          onRevealInFinder(candidate.node.path)
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

  private func deepHotspotsSection(_ snapshot: ScanInsightsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Deep Hotspots")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      VStack(alignment: .leading, spacing: 10) {
        ForEach(snapshot.hotspots) { hotspot in
          hotspotRow(hotspot)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func extensionMixSection(_ snapshot: ScanInsightsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("File Type Mix")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      VStack(alignment: .leading, spacing: 9) {
        ForEach(snapshot.extensionStats) { stat in
          extensionRow(stat)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private func extensionRow(_ stat: ScanInsightsSnapshot.ExtensionStat) -> some View {
    HStack(spacing: 10) {
      Text(stat.label)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .frame(width: 86, alignment: .leading)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous)
            .fill(AppTheme.Colors.surfaceElevated.opacity(0.5))

          Capsule(style: .continuous)
            .fill(AppTheme.Colors.chart2.opacity(0.8))
            .frame(width: max(6, proxy.size.width * max(0, min(1, stat.share))))
        }
      }
      .frame(height: 6)

      Text(ByteFormatter.string(from: stat.sizeBytes))
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 92, alignment: .trailing)

      Text(percentString(stat.share))
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textTertiary)
        .frame(width: 42, alignment: .trailing)
    }
  }

  private func hotspotRow(_ hotspot: ScanInsightsSnapshot.RankedNode) -> some View {
    HStack(spacing: 10) {
      Image(systemName: hotspot.node.isDirectory ? "folder.fill" : "doc.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 2) {
        Text(truncatedPath(hotspot.node.path))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)

        Text("Depth \(hotspot.depth) • \(ByteFormatter.string(from: hotspot.node.sizeBytes)) • \(percentString(hotspot.share))")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }

      Spacer(minLength: 8)

      compactActionButton("Reveal") {
        onRevealInFinder(hotspot.node.path)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
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

  private func riskBadge(_ risk: ScanInsightsSnapshot.CleanupRisk) -> some View {
    Text(risk.title)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(risk.style.foreground)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(risk.style.background)
          .overlay(
            Capsule(style: .continuous)
              .stroke(risk.style.border, lineWidth: 1)
          )
      )
  }

  private func compactActionButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(AppTheme.Colors.textPrimary)
      .padding(.horizontal, 9)
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

  private func percentString(_ ratio: Double) -> String {
    ratio.formatted(.percent.precision(.fractionLength(0)))
  }

  private func displayName(for node: FileNode) -> String {
    if node.name.isEmpty {
      return node.path
    }
    return node.name
  }

  private func truncatedPath(_ path: String) -> String {
    let components = path.split(separator: "/").map(String.init)
    guard components.count > 3 else {
      return path
    }
    return ".../\(components.suffix(3).joined(separator: "/"))"
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
}

private struct ScanInsightsSnapshot: Sendable {
  struct RankedNode: Identifiable, Sendable {
    let node: FileNode
    let depth: Int
    let share: Double

    var id: String { node.id }
  }

  enum CleanupRisk: Sendable {
    case safe
    case review
    case careful

    var title: String {
      switch self {
      case .safe:
        return "SAFE"
      case .review:
        return "REVIEW"
      case .careful:
        return "CAUTION"
      }
    }

    var style: (foreground: Color, background: Color, border: Color) {
      switch self {
      case .safe:
        return (
          AppTheme.Colors.statusSuccessForeground,
          AppTheme.Colors.statusSuccessBackground,
          AppTheme.Colors.statusSuccessBorder
        )
      case .review:
        return (
          AppTheme.Colors.textSecondary,
          AppTheme.Colors.surfaceElevated.opacity(0.75),
          AppTheme.Colors.cardBorder
        )
      case .careful:
        return (
          AppTheme.Colors.statusWarningForeground,
          AppTheme.Colors.statusWarningBackground,
          AppTheme.Colors.statusWarningBorder
        )
      }
    }
  }

  struct CleanupCandidate: Identifiable, Sendable {
    let categoryID: String
    let category: String
    let guidance: String
    let risk: CleanupRisk
    let node: FileNode
    let share: Double

    var id: String { "\(categoryID)|\(node.id)" }
  }

  struct ExtensionStat: Identifiable, Sendable {
    let id: String
    let label: String
    let sizeBytes: Int64
    let share: Double
  }

  let totalSizeBytes: Int64
  let fileCount: Int
  let directoryCount: Int
  let maxDepth: Int
  let topDirectChildren: [RankedNode]
  let hotspots: [RankedNode]
  let cleanupCandidates: [CleanupCandidate]
  let extensionStats: [ExtensionStat]

  init(rootNode: FileNode) {
    let totalBytes = max(rootNode.sizeBytes, 1)
    totalSizeBytes = rootNode.sizeBytes

    topDirectChildren = Array(rootNode.sortedChildrenBySize.prefix(5)).map {
      RankedNode(
        node: $0,
        depth: 1,
        share: Double($0.sizeBytes) / Double(totalBytes)
      )
    }

    var files = 0
    var directories = 0
    var maxObservedDepth = 0
    var topHotspots: [(node: FileNode, depth: Int)] = []
    var cleanupMatches: [String: (rule: CleanupRule, node: FileNode)] = [:]
    var fileBytes = Int64(0)
    var extensionMap: [String: Int64] = [:]

    var stack: [(node: FileNode, depth: Int)] = [(rootNode, 0)]

    while let current = stack.popLast() {
      maxObservedDepth = max(maxObservedDepth, current.depth)

      if current.node.isDirectory {
        directories += 1
      } else {
        files += 1
        fileBytes += current.node.sizeBytes
        let ext = Self.fileExtension(for: current.node)
        extensionMap[ext, default: 0] += current.node.sizeBytes
      }

      if current.depth >= 2 {
        Self.insertTopNode((current.node, current.depth), into: &topHotspots, limit: 5)
      }

      let loweredPath = current.node.path.lowercased()
      for rule in Self.cleanupRules {
        if rule.matches(path: loweredPath) {
          if let existing = cleanupMatches[rule.id], existing.node.sizeBytes >= current.node.sizeBytes {
            continue
          }
          cleanupMatches[rule.id] = (rule: rule, node: current.node)
        }
      }

      if current.node.isDirectory {
        for child in current.node.children {
          stack.append((child, current.depth + 1))
        }
      }
    }

    fileCount = files
    directoryCount = max(0, directories - 1)
    maxDepth = maxObservedDepth

    hotspots = topHotspots.map {
      RankedNode(
        node: $0.node,
        depth: $0.depth,
        share: Double($0.node.sizeBytes) / Double(totalBytes)
      )
    }

    cleanupCandidates = cleanupMatches.values
      .sorted(by: { lhs, rhs in
        lhs.node.sizeBytes > rhs.node.sizeBytes
      })
      .prefix(4)
      .map {
        CleanupCandidate(
          categoryID: $0.rule.id,
          category: $0.rule.title,
          guidance: $0.rule.guidance,
          risk: $0.rule.risk,
          node: $0.node,
          share: Double($0.node.sizeBytes) / Double(totalBytes)
        )
      }

    extensionStats = extensionMap
      .map { ext, sizeBytes in
        ExtensionStat(
          id: ext,
          label: ext == "<none>" ? "No Ext" : ".\(ext)",
          sizeBytes: sizeBytes,
          share: Double(sizeBytes) / Double(max(fileBytes, 1))
        )
      }
      .sorted(by: { lhs, rhs in
        lhs.sizeBytes > rhs.sizeBytes
      })
      .prefix(6)
      .map { $0 }
  }

  private static func insertTopNode(
    _ candidate: (node: FileNode, depth: Int),
    into top: inout [(node: FileNode, depth: Int)],
    limit: Int
  ) {
    if top.count == limit, let last = top.last, candidate.node.sizeBytes <= last.node.sizeBytes {
      return
    }

    var low = 0
    var high = top.count

    while low < high {
      let mid = (low + high) / 2
      if top[mid].node.sizeBytes < candidate.node.sizeBytes {
        high = mid
      } else {
        low = mid + 1
      }
    }

    top.insert(candidate, at: low)
    if top.count > limit {
      top.removeLast()
    }
  }

  private static func fileExtension(for node: FileNode) -> String {
    let ext = URL(fileURLWithPath: node.name).pathExtension.lowercased()
    return ext.isEmpty ? "<none>" : ext
  }

  private struct CleanupRule: Sendable {
    let id: String
    let title: String
    let guidance: String
    let risk: CleanupRisk
    let tokens: [String]

    func matches(path: String) -> Bool {
      tokens.contains(where: { path.contains($0) })
    }
  }

  private static let cleanupRules: [CleanupRule] = [
    CleanupRule(
      id: "cache",
      title: "Caches",
      guidance: "Usually safe to clear, but confirm app behavior first.",
      risk: .safe,
      tokens: ["/library/caches/", "/.cache/", "/caches/"]
    ),
    CleanupRule(
      id: "downloads",
      title: "Downloads",
      guidance: "Review old installers and archives that can be removed or moved.",
      risk: .review,
      tokens: ["/downloads/"]
    ),
    CleanupRule(
      id: "node_modules",
      title: "node_modules",
      guidance: "Dependencies can be regenerated with package managers.",
      risk: .review,
      tokens: ["/node_modules/"]
    ),
    CleanupRule(
      id: "derived-data",
      title: "Xcode DerivedData",
      guidance: "Build artifacts can be deleted and regenerated by Xcode.",
      risk: .safe,
      tokens: ["/library/developer/xcode/deriveddata/"]
    ),
    CleanupRule(
      id: "application-support",
      title: "Application Data",
      guidance: "Potentially important data. Validate before deletion.",
      risk: .careful,
      tokens: ["/library/application support/"]
    )
  ]
}
