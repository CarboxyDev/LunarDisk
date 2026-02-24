import SwiftUI

struct ScanSetupView: View {
  let selectedFolderPath: String?
  let canStartFolderScan: Bool
  let lastFailure: AppModel.ScanFailure?
  let onScanMacintoshHD: () -> Void
  let onChooseFolder: () -> Void
  let onStartFolderScan: () -> Void
  let onOpenFullDiskAccess: () -> Void

  @State private var revealHeader = false
  @State private var revealPrimaryCard = false
  @State private var revealSecondaryStack = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      setupHeader
        .opacity(revealHeader ? 1 : 0)
        .offset(y: revealHeader ? 0 : 14)

      if let failure = lastFailure {
        failureBanner(failure)
          .opacity(revealHeader ? 1 : 0)
          .offset(y: revealHeader ? 0 : 10)
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) {
          folderScanPrimaryCard
            .opacity(revealPrimaryCard ? 1 : 0)
            .offset(y: revealPrimaryCard ? 0 : 12)

          VStack(alignment: .leading, spacing: 16) {
            fullDiskCard
            trustCard
          }
          .frame(width: 360, alignment: .topLeading)
          .opacity(revealSecondaryStack ? 1 : 0)
          .offset(y: revealSecondaryStack ? 0 : 12)
        }

        VStack(alignment: .leading, spacing: 16) {
          folderScanPrimaryCard
            .opacity(revealPrimaryCard ? 1 : 0)
            .offset(y: revealPrimaryCard ? 0 : 12)

          fullDiskCard
            .opacity(revealSecondaryStack ? 1 : 0)
            .offset(y: revealSecondaryStack ? 0 : 12)

          trustCard
            .opacity(revealSecondaryStack ? 1 : 0)
            .offset(y: revealSecondaryStack ? 0 : 12)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animation(.spring(response: 0.44, dampingFraction: 0.88), value: revealHeader)
    .animation(.spring(response: 0.44, dampingFraction: 0.88), value: revealPrimaryCard)
    .animation(.spring(response: 0.44, dampingFraction: 0.88), value: revealSecondaryStack)
    .onAppear {
      animateEntranceIfNeeded()
    }
  }

  private var setupHeader: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Start a New Scan")
        .font(AppTheme.Typography.heroTitle)
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("Folder scan is fastest for iterative cleanup. Full-disk scan is available when you need complete system coverage.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private var folderScanPrimaryCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "folder.fill.badge.gearshape")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Folder Scan")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Recommended")
          .font(.system(size: 11, weight: .semibold))
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

      HStack(spacing: 10) {
        if selectedFolderPath == nil {
          Button {
            onChooseFolder()
          } label: {
            Label("Choose Folder…", systemImage: "folder.badge.plus")
          }
          .buttonStyle(LunarPrimaryButtonStyle())
          .keyboardShortcut("o", modifiers: [.command])
        } else {
          Button {
            onChooseFolder()
          } label: {
            Label("Change Folder…", systemImage: "folder.badge.plus")
          }
          .buttonStyle(LunarSecondaryButtonStyle())
          .keyboardShortcut("o", modifiers: [.command])
        }

        Button("Start Folder Scan") {
          onStartFolderScan()
        }
        .buttonStyle(LunarPrimaryButtonStyle())
        .disabled(!canStartFolderScan)
        .keyboardShortcut(.defaultAction)
      }

      selectedFolderPathSlot
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
        .fill(AppTheme.Colors.surface)
        .overlay(
          RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
            .stroke(AppTheme.Colors.accent.opacity(0.55), lineWidth: 1.1)
        )
        .shadow(color: AppTheme.Colors.shadow, radius: 16, x: 0, y: 8)
    )
  }

  private var fullDiskCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "internaldrive.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Text("Full-Disk Scan")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      Text("Use when you need complete device-level breakdown. This usually takes longer than a folder scan.")
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        Button("Scan Macintosh HD") {
          onScanMacintoshHD()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Spacer(minLength: 0)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .lunarPanelBackground()
  }

  private var trustCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Permissions & Privacy")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("LunarDisk reads metadata only. File contents are never uploaded or persisted.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        setupPoint("If access is denied, open Full Disk Access in macOS Settings.")
        setupPoint("Enable LunarDisk and rerun the scan.")
        setupPoint("Partial scans are flagged so results remain transparent.")
      }

      HStack(spacing: 10) {
        Button("Open Full Disk Access") {
          onOpenFullDiskAccess()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Spacer(minLength: 0)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .lunarPanelBackground()
  }

  private var selectedFolderPathSlot: some View {
    Group {
      if let selectedFolderPath {
        Text(selectedFolderPath)
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .lineLimit(1)
      } else {
        Text("Choose a folder to enable Start Folder Scan")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(AppTheme.Colors.targetBannerBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
    .help(selectedFolderPath ?? "")
  }

  private func setupPoint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Circle()
        .fill(AppTheme.Colors.accent)
        .frame(width: 6, height: 6)
        .padding(.top, 5)

      Text(text)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func animateEntranceIfNeeded() {
    guard !revealHeader, !revealPrimaryCard, !revealSecondaryStack else { return }

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
          .font(.system(size: 14, weight: .semibold))

        Text(copy.title)
          .font(.system(size: 15, weight: .semibold))
      }
      .foregroundStyle(AppTheme.Colors.textPrimary)

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
}
