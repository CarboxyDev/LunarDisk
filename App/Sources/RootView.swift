import AppKit
import CoreScan
import LunardiskAI
import SwiftUI
import Visualization

struct RootView: View {
  private enum Layout {
    static let sectionSpacing: CGFloat = 16
    static let sideColumnWidth: CGFloat = 420
    static let launchpadTwoColumnBreakpoint: CGFloat = 1_060
    static let resultsTwoColumnBreakpoint: CGFloat = 1_180
    static let minimumContentHeight: CGFloat = 520
    static let chartMinSize: CGFloat = 280
    static let chartMaxSize: CGFloat = 560
  }

  @EnvironmentObject private var onboardingState: OnboardingStateStore
  @StateObject private var model = AppModel()
  @AppStorage("hasAcknowledgedDiskScanDisclosure") private var hasAcknowledgedDiskScanDisclosure = false
  @State private var showFullDiskScanDisclosure = false

  var body: some View {
    Group {
      if onboardingState.hasCompletedOnboarding {
        scannerView
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
      } else {
        OnboardingView {
          onboardingState.completeOnboarding()
        }
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: onboardingState.hasCompletedOnboarding)
  }

  private var scannerView: some View {
    ZStack {
      background

      VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
        controls
        content
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .sheet(isPresented: $showFullDiskScanDisclosure) {
      fullDiskScanDisclosureSheet
    }
  }

  private var background: some View {
    AppTheme.Colors.background
      .overlay {
        LinearGradient(
          colors: [
            AppTheme.Colors.appBackgroundGradientStart,
            AppTheme.Colors.appBackgroundGradientEnd
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .ignoresSafeArea()
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Disk Usage")
            .font(AppTheme.Typography.heroTitle)
            .foregroundStyle(AppTheme.Colors.textPrimary)

          Text("Fast local analysis with clear permission controls")
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }

        Spacer()

        statusPill()
      }

      HStack(spacing: 10) {
        Button("Scan Macintosh HD") {
          startMacintoshHDScanFlow()
        }
        .buttonStyle(LunarPrimaryButtonStyle())
        .disabled(model.isScanning)

        Button("Choose Folder…") {
          chooseFolder()
        }
        .buttonStyle(LunarSecondaryButtonStyle())
        .disabled(model.isScanning)

        Button("Scan Selected") {
          model.startScan()
        }
        .buttonStyle(LunarSecondaryButtonStyle())
        .disabled(!model.canStartScan)

        Button("Cancel") {
          model.cancelScan()
        }
        .buttonStyle(LunarSecondaryButtonStyle())
        .opacity(model.isScanning ? 1 : 0)
        .disabled(!model.isScanning)
        .allowsHitTesting(model.isScanning)

        Spacer()
      }
      .frame(maxWidth: .infinity)

      currentTargetBanner
    }
    .padding(16)
    .background(panelBackground())
  }

  private func statusPill() -> some View {
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
    if model.isScanning {
      return (
        title: "Scanning",
        icon: "waveform.path.ecg",
        foreground: AppTheme.Colors.textPrimary,
        background: AppTheme.Colors.statusScanningBackground,
        border: AppTheme.Colors.cardBorder,
        shouldShimmer: true
      )
    }

    if model.rootNode != nil && model.lastFailure == nil {
      return (
        title: "Scan Complete",
        icon: "checkmark.seal.fill",
        foreground: AppTheme.Colors.statusSuccessForeground,
        background: AppTheme.Colors.statusSuccessBackground,
        border: AppTheme.Colors.statusSuccessBorder,
        shouldShimmer: false
      )
    }

    if model.lastFailure != nil {
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
      title: "Idle",
      icon: "circle.fill",
      foreground: AppTheme.Colors.textSecondary,
      background: AppTheme.Colors.statusIdleBackground,
      border: AppTheme.Colors.cardBorder,
      shouldShimmer: false
    )
  }

  @ViewBuilder
  private var currentTargetBanner: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Current target")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      Text(model.selectedURL?.path ?? "No target selected. Use Scan Macintosh HD for a one-click full scan, or choose a specific folder.")
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(model.selectedURL == nil ? AppTheme.Colors.textTertiary : AppTheme.Colors.textSecondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(AppTheme.Colors.targetBannerBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
  }

  private var content: some View {
    Group {
      if model.isScanning {
        loadingState
      } else if let rootNode = model.rootNode {
        resultsContent(rootNode: rootNode)
      } else {
        launchpad
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .frame(minHeight: Layout.minimumContentHeight, alignment: .topLeading)
  }

  private var launchpad: some View {
    GeometryReader { geometry in
      let useSingleColumn = geometry.size.width < Layout.launchpadTwoColumnBreakpoint

      VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
        if let failure = model.lastFailure {
          failureBanner(failure)
        }

        if useSingleColumn {
          VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            quickStartCard
            permissionCard(useFixedWidth: false)
          }
        } else {
          HStack(alignment: .top, spacing: Layout.sectionSpacing) {
            quickStartCard
            permissionCard(useFixedWidth: true)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var quickStartCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "externaldrive.fill")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      Text("Start Your First Scan")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("Use one click to scan your main disk, or pick a specific folder if you want tighter scope.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)

      Divider()
        .overlay(AppTheme.Colors.divider)
        .frame(height: AppTheme.Metrics.dividerHeight)

      VStack(alignment: .leading, spacing: 10) {
        launchPoint("One-click full-disk scan for immediate signal", icon: "bolt.fill")
        launchPoint("Sorted top items and sunburst visualization", icon: "chart.pie.fill")
        launchPoint("No file contents are sent or persisted", icon: "lock.shield.fill")
      }

      HStack(spacing: 10) {
        Button("Scan Macintosh HD") {
          startMacintoshHDScanFlow()
        }
        .buttonStyle(LunarPrimaryButtonStyle())
        .disabled(model.isScanning)

        Button("Choose Folder…") {
          chooseFolder()
        }
        .buttonStyle(LunarSecondaryButtonStyle())
        .disabled(model.isScanning)
      }

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
    .background(panelBackground())
  }

  private func launchPoint(_ text: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 16, height: 16)

      Text(text)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func permissionCard(useFixedWidth: Bool) -> some View {
    let card = VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "hand.raised.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      Text("Permissions, Done Right")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("Lunardisk requests only what it needs. If macOS blocks folders, you can recover with one guided path.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)

      Text("macOS does not have a separate permission for metadata-only reads. During first scan, you may see multiple system prompts for protected locations.")
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)

      Divider()
        .overlay(AppTheme.Colors.divider)
        .frame(height: AppTheme.Metrics.dividerHeight)

      VStack(alignment: .leading, spacing: 10) {
        permissionStep(number: 1, text: "Run Scan Macintosh HD or choose a folder.")
        permissionStep(number: 2, text: "If access is denied, open Full Disk Access settings.")
        permissionStep(number: 3, text: "Enable Lunardisk, then rerun your scan.")
      }

      HStack(spacing: 10) {
        Button("Open Full Disk Access") {
          openFullDiskAccessSettings()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Button("Retry Scan") {
          model.startScan()
        }
        .buttonStyle(LunarSecondaryButtonStyle())
        .disabled(!model.canStartScan)
      }

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(minHeight: 350, alignment: .topLeading)
    .background(panelBackground())

    return Group {
      if useFixedWidth {
        card
          .frame(width: Layout.sideColumnWidth, alignment: .topLeading)
      } else {
        card
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }

  private func permissionStep(number: Int, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text("\(number)")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(AppTheme.Colors.accentForeground)
        .frame(width: 22, height: 22)
        .background(
          Circle()
            .fill(AppTheme.Colors.permissionStepBadgeBackground)
        )

      Text(text)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
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

      HStack(spacing: 10) {
        if copy.suggestPermissionRecovery {
          Button("Open Full Disk Access") {
            openFullDiskAccessSettings()
          }
          .buttonStyle(LunarSecondaryButtonStyle())
        }

        if model.selectedURL != nil {
          Button("Retry") {
            model.startScan()
          }
          .buttonStyle(LunarSecondaryButtonStyle())
          .disabled(model.isScanning)
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
        "macOS blocked access to \(path). Open Full Disk Access, enable Lunardisk, then retry.",
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
        "Could not read \(path): \(message)",
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

  private var loadingState: some View {
    ScanningStatePanel(
      title: "Scanning Your Filesystem",
      message: "Reading metadata and sizes. Protected locations are skipped unless access is granted."
    )
  }

  private func resultsContent(rootNode: FileNode) -> some View {
    GeometryReader { geometry in
      let useSingleColumn = geometry.size.width < Layout.resultsTwoColumnBreakpoint
      let preferredChartSize = min(
        max(geometry.size.width * (useSingleColumn ? 0.74 : 0.42), Layout.chartMinSize),
        Layout.chartMaxSize
      )

      Group {
        if useSingleColumn {
          VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            distributionSection(rootNode: rootNode, chartSize: preferredChartSize)
            supplementalResultsSections(rootNode: rootNode, useFixedWidth: false)
          }
        } else {
          HStack(alignment: .top, spacing: Layout.sectionSpacing) {
            distributionSection(rootNode: rootNode, chartSize: preferredChartSize)
            supplementalResultsSections(rootNode: rootNode, useFixedWidth: true)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func distributionSection(rootNode: FileNode, chartSize: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Distribution")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      SunburstChartView(root: rootNode, palette: AppTheme.Colors.chartPalette)
        .frame(width: chartSize, height: chartSize)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(panelBackground())
  }

  private func supplementalResultsSections(rootNode: FileNode, useFixedWidth: Bool) -> some View {
    let sections = VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
      topItemsSection(rootNode: rootNode)
      insightsSection
    }

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

  private func topItemsSection(rootNode: FileNode) -> some View {
    let items = Array(rootNode.sortedChildrenBySize.prefix(25))

    return VStack(alignment: .leading, spacing: 10) {
      Text("Top Items")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, child in
            HStack(spacing: 10) {
              Text(child.name)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)

              Spacer()

              Text(ByteFormatter.string(from: child.sizeBytes))
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .padding(.vertical, 8)

            if index != items.count - 1 {
              Rectangle()
                .fill(AppTheme.Colors.divider)
                .frame(height: AppTheme.Metrics.dividerHeight)
            }
          }
        }
      }
      .frame(maxHeight: 300)
    }
    .padding(16)
    .background(panelBackground())
  }

  private var insightsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Insights")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      if model.insights.isEmpty {
        Text("No insights available for this scan.")
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textTertiary)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(model.insights) { insight in
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: insight.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.Colors.textSecondary)

              Text(insight.message)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
    .padding(16)
    .background(panelBackground())
  }

  private func statePanel(icon: String, title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text(message)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(panelBackground())
  }

  private func panelBackground() -> some View {
    RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
      .fill(AppTheme.Colors.surface)
      .overlay(
        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
          .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
      )
      .shadow(color: AppTheme.Colors.shadow, radius: 16, x: 0, y: 8)
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose folder to scan"
    panel.prompt = "Select"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false

    if panel.runModal() == .OK {
      model.selectScanTarget(panel.url)
    }
  }

  private var fullDiskScanDisclosureSheet: some View {
    VStack(spacing: 18) {
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [
                AppTheme.Colors.surfaceElevated,
                AppTheme.Colors.surface
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            Circle()
              .stroke(AppTheme.Colors.cardBorder, lineWidth: 1)
          )
          .frame(width: 88, height: 88)
          .shadow(color: AppTheme.Colors.sheetIconShadow, radius: 18, x: 0, y: 8)

        Image(systemName: "info.circle.fill")
          .font(.system(size: 40, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      VStack(spacing: 8) {
        Text("Before Full-Disk Scan")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Lunardisk reads metadata only, not file contents.")
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }
      .multilineTextAlignment(.center)

      VStack(alignment: .leading, spacing: 10) {
        disclosurePoint("Reads names, paths, directory structure, and byte sizes.")
        disclosurePoint("Does not upload data or store file contents.")
        disclosurePoint("macOS may show several prompts for protected areas on first run.")
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(AppTheme.Colors.disclosureCalloutBackground)
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
          )
      )

      HStack(spacing: 10) {
        Button("Continue Scan") {
          hasAcknowledgedDiskScanDisclosure = true
          showFullDiskScanDisclosure = false
          model.scanMacintoshHD()
        }
        .buttonStyle(LunarPrimaryButtonStyle())

        Button("Open Full Disk Access") {
          showFullDiskScanDisclosure = false
          openFullDiskAccessSettings()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Spacer()

        Button("Cancel") {
          showFullDiskScanDisclosure = false
        }
        .buttonStyle(LunarSecondaryButtonStyle())
      }
      .padding(.top, 2)
    }
    .padding(26)
    .frame(width: 620)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(AppTheme.Colors.surface)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
  }

  private func disclosurePoint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .padding(.top, 2)

      Text(text)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func startMacintoshHDScanFlow() {
    if hasAcknowledgedDiskScanDisclosure {
      model.scanMacintoshHD()
      return
    }
    showFullDiskScanDisclosure = true
  }

  private func openFullDiskAccessSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
      "x-apple.systempreferences:com.apple.preference.security?Privacy"
    ]

    for rawURL in candidates {
      guard let url = URL(string: rawURL) else { continue }
      if NSWorkspace.shared.open(url) {
        return
      }
    }
  }
}

private struct ScanningStatePanel: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      AnimatedScanGlyph()

      Text(title)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text(message)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 8) {
        loadingRow(width: 0.92)
        loadingRow(width: 0.72)
        loadingRow(width: 0.84)
      }
      .padding(.top, 4)

      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
          .tint(AppTheme.Colors.textSecondary)
        Text("Calculating sizes…")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }
      .padding(.top, 2)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
        .fill(AppTheme.Colors.surface)
        .overlay(
          RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
        .shadow(color: AppTheme.Colors.shadow, radius: 16, x: 0, y: 8)
    )
  }

  private func loadingRow(width: CGFloat) -> some View {
    GeometryReader { proxy in
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(AppTheme.Colors.scanningSkeleton)
        .frame(width: proxy.size.width * width, height: 10)
        .lunarShimmer(active: true)
    }
    .frame(height: 10)
  }
}

private struct AnimatedScanGlyph: View {
  @State private var isAnimating = false

  var body: some View {
    ZStack {
      Circle()
        .fill(AppTheme.Colors.scanningGlyphBackground)
        .frame(width: 70, height: 70)

      Circle()
        .trim(from: 0.16, to: 0.96)
        .stroke(
          AppTheme.Colors.scanningGlyphRing,
          style: StrokeStyle(lineWidth: 2.1, lineCap: .round)
        )
        .frame(width: 70, height: 70)
        .rotationEffect(.degrees(isAnimating ? 360 : 0))
        .animation(.linear(duration: 1.9).repeatForever(autoreverses: false), value: isAnimating)

      Image(systemName: "magnifyingglass")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .scaleEffect(isAnimating ? 1.08 : 0.92)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
    }
    .onAppear {
      isAnimating = true
    }
  }
}

private struct LunarShimmerModifier: ViewModifier {
  let active: Bool
  @State private var phase: CGFloat = -1

  func body(content: Content) -> some View {
    content
      .overlay {
        if active {
          GeometryReader { proxy in
            let width = max(proxy.size.width, 120)
            LinearGradient(
              colors: [
                .clear,
                AppTheme.Colors.shimmerHighlight,
                .clear
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(width: width * 0.34)
            .blur(radius: 6)
            .offset(x: phase * (width + 120))
            .onAppear {
              phase = -1
              withAnimation(.linear(duration: 1.55).repeatForever(autoreverses: false)) {
                phase = 1
              }
            }
          }
          .allowsHitTesting(false)
          .mask(content)
        }
      }
  }
}

private extension View {
  func lunarShimmer(active: Bool) -> some View {
    modifier(LunarShimmerModifier(active: active))
  }
}
