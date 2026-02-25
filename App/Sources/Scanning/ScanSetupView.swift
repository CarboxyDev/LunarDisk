import AppKit
import SwiftUI

struct ScanSetupView: View {
  private enum Layout {
    static let sectionSpacing: CGFloat = AppTheme.Metrics.cardSpacing
    static let headerSpacing: CGFloat = AppTheme.Metrics.titleSpacing
    static let cardPadding: CGFloat = 16
    static let primaryCardSpacing: CGFloat = 14
    static let standardCardSpacing: CGFloat = 12
    static let buttonRowSpacing: CGFloat = 10
    static let pointSpacing: CGFloat = 10
    static let pathSlotHorizontalPadding: CGFloat = 10
    static let pathSlotVerticalPadding: CGFloat = 8
    static let pathSlotCornerRadius: CGFloat = 8
    static let secondaryColumnMinWidth: CGFloat = 300
    static let secondaryColumnIdealWidth: CGFloat = 360
    static let secondaryColumnMaxWidth: CGFloat = 420
    static let entranceOffsetHeader: CGFloat = 14
    static let entranceOffsetCard: CGFloat = 12
  }

  let selectedFolderPath: String?
  let canStartFolderScan: Bool
  let lastFailure: AppModel.ScanFailure?
  let onScanMacintoshHD: () -> Void
  let onChooseFolder: () -> Void
  let onStartFolderScan: () -> Void
  let onOpenFullDiskAccess: () -> Void
  let onRevealInFinder: (String) -> Void

  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @State private var revealHeader = false
  @State private var revealPrimaryCard = false
  @State private var revealSecondaryStack = false

  private var hasSelectedFolder: Bool {
    selectedFolderPath != nil
  }

  private var entranceAnimation: Animation? {
    accessibilityReduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.88)
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

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: Layout.sectionSpacing) {
          folderScanPrimaryCard
            .opacity(revealPrimaryCard ? 1 : 0)
            .offset(y: revealPrimaryCard ? 0 : Layout.entranceOffsetCard)

          VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            fullDiskCard
            trustCard
          }
          .frame(
            minWidth: Layout.secondaryColumnMinWidth,
            idealWidth: Layout.secondaryColumnIdealWidth,
            maxWidth: Layout.secondaryColumnMaxWidth,
            alignment: .topLeading
          )
          .opacity(revealSecondaryStack ? 1 : 0)
          .offset(y: revealSecondaryStack ? 0 : Layout.entranceOffsetCard)
        }

        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
          folderScanPrimaryCard
            .opacity(revealPrimaryCard ? 1 : 0)
            .offset(y: revealPrimaryCard ? 0 : Layout.entranceOffsetCard)

          fullDiskCard
            .opacity(revealSecondaryStack ? 1 : 0)
            .offset(y: revealSecondaryStack ? 0 : Layout.entranceOffsetCard)

          trustCard
            .opacity(revealSecondaryStack ? 1 : 0)
            .offset(y: revealSecondaryStack ? 0 : Layout.entranceOffsetCard)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animation(entranceAnimation, value: revealHeader)
    .animation(entranceAnimation, value: revealPrimaryCard)
    .animation(entranceAnimation, value: revealSecondaryStack)
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

      Text("Folder scan is fastest for iterative cleanup. Full-disk scan is available when you need complete system coverage.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)
    }
    .lunarSetupCard(padding: Layout.cardPadding)
  }

  private var folderScanPrimaryCard: some View {
    VStack(alignment: .leading, spacing: Layout.primaryCardSpacing) {
      HStack(alignment: .center, spacing: Layout.pointSpacing) {
        Image(systemName: "folder.fill.badge.gearshape")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Folder Scan")
          .font(AppTheme.Typography.cardHeader)
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Recommended")
          .font(AppTheme.Typography.microStrong)
          .foregroundStyle(AppTheme.Colors.accentForeground)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            Capsule(style: .continuous)
              .fill(AppTheme.Colors.accent)
          )
      }

      Text("Use this for fast, focused scans on Downloads, project directories, or any area you are actively cleaning.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: Layout.buttonRowSpacing) {
        if hasSelectedFolder {
          Button {
            onChooseFolder()
          } label: {
            Label("Change Folder…", systemImage: "folder.badge.plus")
          }
          .buttonStyle(LunarSecondaryButtonStyle())
          .keyboardShortcut("o", modifiers: [.command])

          Button("Start Folder Scan") {
            onStartFolderScan()
          }
          .buttonStyle(LunarPrimaryButtonStyle())
          .disabled(!canStartFolderScan)
          .keyboardShortcut(.defaultAction)
        } else {
          Button {
            onChooseFolder()
          } label: {
            Label("Choose Folder…", systemImage: "folder.badge.plus")
          }
          .buttonStyle(LunarPrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
        }

        Spacer(minLength: 0)
      }

      selectedFolderPathSlot
    }
    .lunarSetupCard(tone: .emphasis, padding: Layout.cardPadding)
  }

  private var fullDiskCard: some View {
    VStack(alignment: .leading, spacing: Layout.standardCardSpacing) {
      HStack(spacing: 8) {
        Image(systemName: "internaldrive.fill")
          .font(AppTheme.Typography.captionStrong)
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Text("Full-Disk Scan")
          .font(AppTheme.Typography.sectionHeader)
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      Text("Use when you need complete device-level breakdown. This usually takes longer than a folder scan.")
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
    }
    .lunarSetupCard(padding: Layout.cardPadding)
  }

  private var trustCard: some View {
    VStack(alignment: .leading, spacing: Layout.primaryCardSpacing) {
      Text("Permissions & Privacy")
        .font(AppTheme.Typography.sectionHeader)
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("LunarDisk reads metadata only. File contents are never uploaded or persisted.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: Layout.pointSpacing) {
        setupPoint("If access is denied, open Full Disk Access in macOS Settings.")
        setupPoint("Enable LunarDisk and rerun the scan.")
        setupPoint("Partial scans are flagged so results remain transparent.")
      }

      HStack(spacing: Layout.buttonRowSpacing) {
        Button("Open Full Disk Access") {
          onOpenFullDiskAccess()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Spacer(minLength: 0)
      }
    }
    .lunarSetupCard(padding: Layout.cardPadding)
  }

  private var selectedFolderPathSlot: some View {
    VStack(alignment: .leading, spacing: 8) {
      Group {
        if let selectedFolderPath {
          Text(selectedFolderPath)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
        } else {
          Text("Choose a folder to enable Start Folder Scan")
            .font(AppTheme.Typography.micro)
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .lineLimit(1)
        }
      }

      if let selectedFolderPath {
        HStack(spacing: 8) {
          pathActionChip(
            title: "Copy Path",
            systemImage: "doc.on.doc",
            action: { copyToPasteboard(selectedFolderPath) }
          )
          .keyboardShortcut("c", modifiers: [.command, .shift])
          .help("Copy selected folder path (⌘⇧C)")
          .accessibilityHint("Copies the selected folder path to the clipboard.")

          pathActionChip(
            title: "Reveal",
            systemImage: "folder",
            action: { onRevealInFinder(selectedFolderPath) }
          )
          .keyboardShortcut("r", modifiers: [.command, .shift])
          .help("Reveal selected folder in Finder (⌘⇧R)")
          .accessibilityHint("Opens Finder with the selected folder highlighted.")

          Spacer(minLength: 0)
        }
      }
    }
    .padding(.horizontal, Layout.pathSlotHorizontalPadding)
    .padding(.vertical, Layout.pathSlotVerticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Layout.pathSlotCornerRadius, style: .continuous)
        .fill(AppTheme.Colors.targetBannerBackground)
        .overlay(
          RoundedRectangle(cornerRadius: Layout.pathSlotCornerRadius, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
    .help(selectedFolderPath ?? "")
  }

  private func pathActionChip(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(AppTheme.Typography.microStrong)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
          Capsule(style: .continuous)
            .fill(AppTheme.Colors.surfaceElevated.opacity(0.62))
            .overlay(
              Capsule(style: .continuous)
                .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
            )
        )
    }
    .buttonStyle(.plain)
  }

  private func copyToPasteboard(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
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
    guard !revealHeader, !revealPrimaryCard, !revealSecondaryStack else { return }

    if accessibilityReduceMotion {
      revealHeader = true
      revealPrimaryCard = true
      revealSecondaryStack = true
      return
    }

    Task { @MainActor in
      revealHeader = true
      try? await Task.sleep(nanoseconds: 90_000_000)
      revealPrimaryCard = true
      try? await Task.sleep(nanoseconds: 90_000_000)
      revealSecondaryStack = true
    }
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
