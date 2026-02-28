import CoreScan
import SwiftUI

struct ScanSetupView: View {
  private enum Layout {
    static let sectionSpacing: CGFloat = AppTheme.Metrics.cardSpacing
    static let headerSpacing: CGFloat = AppTheme.Metrics.titleSpacing
    static let cardPadding: CGFloat = 18
    static let primaryCardSpacing: CGFloat = 14
    static let standardCardSpacing: CGFloat = 12
    static let subsectionSpacing: CGFloat = 8
    static let buttonRowSpacing: CGFloat = 10
    static let actionTopSpacing: CGFloat = 10
    static let pointSpacing: CGFloat = 9
    static let targetRowMaxWidth: CGFloat = 560
    static let entranceOffsetHeader: CGFloat = 14
    static let entranceOffsetCard: CGFloat = 12
  }

  let selectedFolderPath: String?
  let canStartFolderScan: Bool
  let lastFailure: AppModel.ScanFailure?
  let recentScans: [ScanSummary]
  let onScanMacintoshHD: () -> Void
  let onChooseFolder: () -> Void
  let onStartFolderScan: () -> Void
  let onOpenFullDiskAccess: () -> Void
  let onSelectRecentScan: (String) -> Void

  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @State private var revealHeader = false
  @State private var revealPrimaryCard = false
  @State private var revealSupportCard = false
  @State private var revealRecentScans = false

  private var hasSelectedFolder: Bool {
    selectedFolderPath != nil
  }

  private var entranceAnimation: Animation? {
    accessibilityReduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
      setupHeader
        .opacity(revealHeader ? 1 : 0)
        .offset(y: revealHeader ? 0 : Layout.entranceOffsetHeader)

      if let failure = lastFailure {
        failureBanner(failure)
          .opacity(revealHeader ? 1 : 0)
          .offset(y: revealHeader ? 0 : Layout.entranceOffsetCard)
      }

      primaryWorkflowCard
        .opacity(revealPrimaryCard ? 1 : 0)
        .offset(y: revealPrimaryCard ? 0 : Layout.entranceOffsetCard)

      permissionsAndPrivacyCard
        .opacity(revealSupportCard ? 1 : 0)
        .offset(y: revealSupportCard ? 0 : Layout.entranceOffsetCard)

      if !recentScans.isEmpty {
        recentScansCard
          .opacity(revealRecentScans ? 1 : 0)
          .offset(y: revealRecentScans ? 0 : Layout.entranceOffsetCard)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animation(entranceAnimation, value: revealHeader)
    .animation(entranceAnimation, value: revealPrimaryCard)
    .animation(entranceAnimation, value: revealSupportCard)
    .animation(entranceAnimation, value: revealRecentScans)
    .onAppear {
      animateEntranceIfNeeded()
    }
  }

  private var setupHeader: some View {
    VStack(alignment: .leading, spacing: Layout.headerSpacing) {
      HStack(alignment: .center, spacing: 10) {
        LunarAppIcon(size: .section)

        Text("Start a New Scan")
          .font(AppTheme.Typography.heroTitle)
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      Text("Choose a scan target and start. Folder scan is the default for fast cleanup. Full-disk scan is available when you need complete coverage.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)
    }
    .lunarSetupCard(padding: Layout.cardPadding)
  }

  private var primaryWorkflowCard: some View {
    VStack(alignment: .leading, spacing: Layout.primaryCardSpacing) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "folder.fill.badge.gearshape")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Folder Scan")
          .font(AppTheme.Typography.cardHeader)
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      Text("Use folder scan for quick cleanup loops in Downloads, projects, and specific paths you are actively managing.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      folderTargetPreview
      folderActionRow

      Divider()
        .overlay(AppTheme.Colors.divider)

      fullDiskActionBlock
        .padding(.top, 2)
    }
    .lunarSetupCard(tone: .emphasis, padding: Layout.cardPadding)
  }

  private var folderTargetPreview: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Target")
        .font(AppTheme.Typography.microStrong)
        .foregroundStyle(AppTheme.Colors.textSecondary)

      HStack(spacing: 8) {
        Image(systemName: hasSelectedFolder ? "folder.fill" : "folder")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(hasSelectedFolder ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)

        Text(selectedFolderPath ?? "No folder selected.")
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .foregroundStyle(hasSelectedFolder ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .frame(maxWidth: Layout.targetRowMaxWidth, alignment: .leading)
    .help(selectedFolderPath ?? "No folder selected.")
  }

  private var folderActionRow: some View {
    HStack(spacing: Layout.buttonRowSpacing) {
      Button("Start Folder Scan") {
        onStartFolderScan()
      }
      .buttonStyle(LunarPrimaryButtonStyle())
      .disabled(!canStartFolderScan || !hasSelectedFolder)
      .keyboardShortcut(.defaultAction)

      Button {
        onChooseFolder()
      } label: {
        Label(hasSelectedFolder ? "Change Folder…" : "Choose Folder…", systemImage: "folder.badge.plus")
      }
      .buttonStyle(LunarSecondaryButtonStyle())
      .keyboardShortcut("o", modifiers: [.command])

      Spacer(minLength: 0)
    }
  }

  private var fullDiskActionBlock: some View {
    VStack(alignment: .leading, spacing: Layout.subsectionSpacing) {
      HStack(alignment: .center, spacing: 8) {
        Image(systemName: "internaldrive.fill")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Text("Need Full Coverage?")
          .font(AppTheme.Typography.sectionHeader)
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      Text("Run a full-disk scan to include the whole device. This typically takes longer and may trigger permission prompts.")
        .font(AppTheme.Typography.caption)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: Layout.buttonRowSpacing) {
        Button("Scan Macintosh HD") {
          onScanMacintoshHD()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Spacer(minLength: 0)
      }
      .padding(.top, Layout.actionTopSpacing)
    }
  }

  private var permissionsAndPrivacyCard: some View {
    VStack(alignment: .leading, spacing: Layout.standardCardSpacing) {
      Text("Permissions & Privacy")
        .font(AppTheme.Typography.sectionHeader)
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("LunarDisk scans metadata only. File contents are never uploaded or persisted. If macOS blocks access, use Full Disk Access and rerun.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: Layout.pointSpacing) {
        setupPoint("Reads names, paths, hierarchy, and byte sizes.")
        setupPoint("Stores only minimal local state needed for app flow.")
        setupPoint("Enable LunarDisk in Full Disk Access if a scan fails due to permissions.")
        setupPoint("Partial scans are labeled so totals stay transparent.")
      }

      HStack(spacing: Layout.buttonRowSpacing) {
        Button("Open Full Disk Access") {
          onOpenFullDiskAccess()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Spacer(minLength: 0)
      }
      .padding(.top, Layout.actionTopSpacing)
    }
    .lunarSetupCard(padding: Layout.cardPadding)
  }

  private func setupPoint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Circle()
        .fill(AppTheme.Colors.accent)
        .frame(width: 6, height: 6)
        .padding(.top, 5)

      Text(text)
        .font(AppTheme.Typography.caption)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func animateEntranceIfNeeded() {
    guard !revealHeader, !revealPrimaryCard, !revealSupportCard else { return }

    if accessibilityReduceMotion {
      revealHeader = true
      revealPrimaryCard = true
      revealSupportCard = true
      revealRecentScans = true
      return
    }

    Task { @MainActor in
      revealHeader = true
      try? await Task.sleep(nanoseconds: 85_000_000)
      revealPrimaryCard = true
      try? await Task.sleep(nanoseconds: 85_000_000)
      revealSupportCard = true
      try? await Task.sleep(nanoseconds: 85_000_000)
      revealRecentScans = true
    }
  }

  private var recentScansCard: some View {
    VStack(alignment: .leading, spacing: Layout.standardCardSpacing) {
      HStack(alignment: .center, spacing: 8) {
        Image(systemName: "clock.arrow.circlepath")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Recent Scans")
          .font(AppTheme.Typography.sectionHeader)
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      VStack(spacing: 0) {
        ForEach(recentScans) { scan in
          recentScanRow(scan)

          if scan.id != recentScans.last?.id {
            Divider()
              .overlay(AppTheme.Colors.divider)
          }
        }
      }
    }
    .lunarSetupCard(padding: Layout.cardPadding)
  }

  private func recentScanRow(_ scan: ScanSummary) -> some View {
    Button {
      onSelectRecentScan(scan.targetPath)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: scan.targetPath == "/" ? "internaldrive.fill" : "folder.fill")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(scan.targetPath == "/" ? "Macintosh HD" : scan.targetPath)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)

          Text(relativeDate(scan.timestamp))
            .font(AppTheme.Typography.micro)
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }

        Spacer(minLength: 4)

        Text(ByteFormatter.string(from: scan.totalSizeBytes))
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func failureBanner(_ failure: AppModel.ScanFailure) -> some View {
    let copy = failureCopy(for: failure)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: copy.icon)
          .font(AppTheme.Typography.captionStrong)

        Text(copy.title)
          .font(AppTheme.Typography.sectionHeader)
      }
      .foregroundStyle(AppTheme.Colors.statusWarningForeground)

      Text(copy.message)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if copy.suggestPermissionRecovery {
        Button("Open Full Disk Access") {
          onOpenFullDiskAccess()
        }
        .buttonStyle(LunarSecondaryButtonStyle())
      }
    }
    .lunarSetupCard(tone: .warning, padding: Layout.cardPadding)
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
}
