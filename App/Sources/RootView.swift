import AppKit
import CoreScan
import LunardiskAI
import SwiftUI
import Visualization

struct RootView: View {
  private enum FocusTarget: Hashable {
    case folderScanStartButton
  }

  private enum Layout {
    static let sectionSpacing: CGFloat = 16
    static let sideColumnWidth: CGFloat = 420
    static let launchpadTwoColumnBreakpoint: CGFloat = 1_060
    static let resultsTwoColumnBreakpoint: CGFloat = 1_180
    static let minimumContentHeight: CGFloat = 520
    static let chartMinHeight: CGFloat = 340
    static let chartMaxHeight: CGFloat = 620
    static let scanActionCardHeight: CGFloat = 164
    static let scanStatusRowHeight: CGFloat = 34
  }

  @EnvironmentObject private var onboardingState: OnboardingStateStore
  @StateObject private var model = AppModel()
  @AppStorage("hasAcknowledgedDiskScanDisclosure") private var hasAcknowledgedDiskScanDisclosure = false
  @State private var showFullDiskScanDisclosure = false
  @FocusState private var focusedTarget: FocusTarget?

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
          Text("Scan Storage")
            .font(AppTheme.Typography.heroTitle)
            .foregroundStyle(AppTheme.Colors.textPrimary)

          Text("Choose a full-disk or folder scan. Lunardisk stays local and reads metadata only.")
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }

        Spacer()

        statusPill()
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 12) {
          fullDiskActionCard
          folderScanActionCard
        }

        VStack(alignment: .leading, spacing: 12) {
          fullDiskActionCard
          folderScanActionCard
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      scanStatusRow
    }
    .padding(16)
    .lunarPanelBackground()
  }

  private var scanStatusRow: some View {
    HStack(spacing: 10) {
      Group {
        if model.isScanning, let selectedURL = model.selectedURL {
          Label(scanningTargetText(for: selectedURL), systemImage: "scope")
            .lineLimit(1)
        } else {
          Label("Ready to scan", systemImage: "scope")
        }
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(AppTheme.Colors.textSecondary)

      Spacer()

      Button("Cancel Scan") {
        model.cancelScan()
      }
      .buttonStyle(LunarDestructiveButtonStyle())
      .keyboardShortcut(.cancelAction)
      .opacity(model.isScanning ? 1 : 0)
      .allowsHitTesting(model.isScanning)
      .disabled(!model.isScanning)
      .accessibilityHidden(!model.isScanning)
    }
    .frame(height: Layout.scanStatusRowHeight)
    .padding(.top, 2)
  }

  private var fullDiskActionCard: some View {
    scanActionCard(
      icon: "internaldrive.fill",
      title: "Full-Disk Scan",
      subtitle: "Fastest path to a complete storage map."
    ) {
      Button("Scan Macintosh HD") {
        startMacintoshHDScanFlow()
      }
      .buttonStyle(LunarPrimaryButtonStyle())
      .disabled(model.isScanning)
    }
  }

  private var folderScanActionCard: some View {
    let shouldEmphasizeChooseFolder = selectedFolderURL == nil

    return scanActionCard(
      icon: "folder.fill.badge.gearshape",
      title: "Folder Scan",
      subtitle: "Choose scope first, then run the scan."
    ) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          if shouldEmphasizeChooseFolder {
            Button {
              chooseFolder()
            } label: {
              Label("Choose Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(LunarPrimaryButtonStyle())
            .disabled(model.isScanning)
            .keyboardShortcut("o", modifiers: [.command])
          } else {
            Button {
              chooseFolder()
            } label: {
              Label("Choose Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(LunarSecondaryButtonStyle())
            .disabled(model.isScanning)
            .keyboardShortcut("o", modifiers: [.command])
          }

          Button("Scan Selected Folder") {
            model.startScan()
          }
          .buttonStyle(LunarPrimaryButtonStyle())
          .disabled(!model.canStartScan)
          .keyboardShortcut(.defaultAction)
          .focusable()
          .focused($focusedTarget, equals: .folderScanStartButton)
        }

        selectedFolderPathSlot
      }
    }
  }

  private var selectedFolderPathSlot: some View {
    Group {
      if let selectedFolderURL {
        Text(selectedFolderURL.path)
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .lineLimit(1)
      } else {
        Text(" ")
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .hidden()
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(AppTheme.Colors.targetBannerBackground.opacity(selectedFolderURL == nil ? 0 : 1))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              AppTheme.Colors.cardBorder.opacity(selectedFolderURL == nil ? 0 : 1),
              lineWidth: AppTheme.Metrics.cardBorderWidth
            )
        )
    )
    .accessibilityHidden(selectedFolderURL == nil)
    .help(selectedFolderURL?.path ?? "")
  }

  private var selectedFolderURL: URL? {
    guard let selectedURL = model.selectedURL, selectedURL.path != "/" else {
      return nil
    }
    return selectedURL
  }

  private func scanActionCard<Content: View>(
    icon: String,
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }

      Text(subtitle)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      content()
    }
    .padding(12)
    .frame(
      maxWidth: .infinity,
      minHeight: Layout.scanActionCardHeight,
      maxHeight: Layout.scanActionCardHeight,
      alignment: .topLeading
    )
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.72))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
  }

  private func scanningTargetText(for url: URL) -> String {
    if url.path == "/" {
      return "Scanning Macintosh HD"
    }
    return "Scanning \(url.path)"
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
      Image(systemName: "chart.xyaxis.line")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      Text("What You Get After a Scan")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("The scan output is built to surface storage pressure quickly, with enough detail to act safely.")
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textTertiary)

      Divider()
        .overlay(AppTheme.Colors.divider)
        .frame(height: AppTheme.Metrics.dividerHeight)

      VStack(alignment: .leading, spacing: 10) {
        launchPoint("Treemap breakdown of space usage by folder and size", icon: "chart.bar.xaxis")
        launchPoint("Top items list with direct and deep views", icon: "list.number")
        launchPoint("Heuristic insights for quick cleanup direction", icon: "lightbulb.fill")
        launchPoint("No file contents are uploaded or persisted", icon: "lock.shield.fill")
      }

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
    .lunarPanelBackground()
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
    .lunarPanelBackground()

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
      title: "Scanning Storage",
      message: "Reading directory metadata and calculating cumulative sizes locally on your Mac.",
      steps: [
        "Discovering files and folders",
        "Aggregating nested directory sizes",
        "Preparing ranked results and insights"
      ]
    )
  }

  private func resultsContent(rootNode: FileNode) -> some View {
    GeometryReader { geometry in
      let useSingleColumn = geometry.size.width < Layout.resultsTwoColumnBreakpoint
      let preferredChartHeight = min(
        max(geometry.size.width * (useSingleColumn ? 0.46 : 0.34), Layout.chartMinHeight),
        Layout.chartMaxHeight
      )

      Group {
        if useSingleColumn {
          VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            distributionSection(rootNode: rootNode, chartHeight: preferredChartHeight)
            supplementalResultsSections(rootNode: rootNode, useFixedWidth: false)
          }
        } else {
          HStack(alignment: .top, spacing: Layout.sectionSpacing) {
            distributionSection(rootNode: rootNode, chartHeight: preferredChartHeight)
            supplementalResultsSections(rootNode: rootNode, useFixedWidth: true)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func distributionSection(rootNode: FileNode, chartHeight: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Storage Breakdown")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.textSecondary)
          Text("Treemap distribution for \(displayName(for: rootNode))")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppTheme.Colors.textTertiary)
        }

        Spacer()

        Text(ByteFormatter.string(from: rootNode.sizeBytes))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }

      TreemapChartView(root: rootNode, palette: AppTheme.Colors.chartPalette)
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.Colors.surfaceElevated.opacity(0.38))
            .overlay(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Colors.cardBorder.opacity(0.8), lineWidth: AppTheme.Metrics.cardBorderWidth)
            )
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .lunarPanelBackground()
  }

  private func supplementalResultsSections(rootNode: FileNode, useFixedWidth: Bool) -> some View {
    let sections = VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
      TopItemsPanel(rootNode: rootNode, onRevealInFinder: revealInFinder(path:))
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

  private func displayName(for node: FileNode) -> String {
    if node.path == "/" {
      return "Macintosh HD"
    }
    if node.name.isEmpty {
      return node.path
    }
    return node.name
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
    .lunarPanelBackground()
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
      focusFolderScanStartButtonAfterSelection()
    }
  }

  private func focusFolderScanStartButtonAfterSelection() {
    Task { @MainActor in
      await Task.yield()
      guard model.canStartScan else { return }
      focusedTarget = .folderScanStartButton

      // NSOpenPanel dismissal can briefly steal first responder; retry once.
      try? await Task.sleep(nanoseconds: 120_000_000)
      guard model.canStartScan else { return }
      focusedTarget = .folderScanStartButton
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

  private func revealInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
