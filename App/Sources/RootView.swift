import AppKit
import SwiftUI

struct RootView: View {
  private enum ScanStage {
    case setup
    case session
  }

  @EnvironmentObject private var onboardingState: OnboardingStateStore
  @StateObject private var model = AppModel()
  @AppStorage(PersistedState.fullDiskScanDisclosureAcknowledgedKey) private var hasAcknowledgedDiskScanDisclosure = false
  @State private var showFullDiskScanDisclosure = false
  @State private var stage: ScanStage = .setup

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

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 18) {
          stageContent
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .sheet(isPresented: $showFullDiskScanDisclosure) {
      fullDiskScanDisclosureSheet
    }
    .onAppear {
      syncStageWithModel()
    }
    .onChange(of: model.isScanning) { _, _ in
      syncStageWithModel()
    }
    .onChange(of: model.rootNode?.id) { _, _ in
      syncStageWithModel()
    }
    .onChange(of: model.lastFailure) { _, _ in
      syncStageWithModel()
    }
    .animation(.spring(response: 0.42, dampingFraction: 0.9), value: stageIdentity)
  }

  @ViewBuilder
  private var stageContent: some View {
    switch stage {
    case .setup:
      ScanSetupView(
        selectedFolderPath: selectedFolderURL?.path,
        canStartFolderScan: model.canStartScan,
        lastFailure: model.lastFailure,
        onScanMacintoshHD: startMacintoshHDScanFlow,
        onChooseFolder: chooseFolder,
        onStartFolderScan: startFolderScan,
        onOpenFullDiskAccess: openFullDiskAccessSettings
      )
      .transition(
        .asymmetric(
          insertion: .opacity.combined(with: .move(edge: .leading)),
          removal: .opacity.combined(with: .move(edge: .top))
        )
      )

    case .session:
      ScanSessionView(
        selectedURL: model.selectedURL,
        rootNode: model.rootNode,
        insights: model.insights,
        isScanning: model.isScanning,
        scanProgress: model.scanProgress,
        warningMessage: model.scanWarningMessage,
        failure: model.lastFailure,
        canStartScan: model.canStartScan,
        onCancelScan: model.cancelScan,
        onRetryScan: startCurrentTargetScan,
        onBackToSetup: returnToSetup,
        onOpenFullDiskAccess: openFullDiskAccessSettings,
        onRevealInFinder: revealInFinder(path:)
      )
      .transition(
        .asymmetric(
          insertion: .opacity.combined(with: .move(edge: .trailing)),
          removal: .opacity.combined(with: .move(edge: .bottom))
        )
      )
    }
  }

  private var stageIdentity: String {
    switch stage {
    case .setup:
      return "setup"
    case .session:
      return "session"
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

  private var selectedFolderURL: URL? {
    guard let selectedURL = model.selectedURL, selectedURL.path != "/" else {
      return nil
    }
    return selectedURL
  }

  private func syncStageWithModel() {
    let shouldShowSession = model.isScanning || model.rootNode != nil || model.lastFailure != nil
    stage = shouldShowSession ? .session : .setup
  }

  private func startFolderScan() {
    guard model.canStartScan else { return }
    withAnimation {
      stage = .session
    }
    model.startScan()
  }

  private func startCurrentTargetScan() {
    guard model.canStartScan else { return }
    withAnimation {
      stage = .session
    }
    model.startScan()
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose Folder to Scan"
    panel.prompt = "Select"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false

    if panel.runModal() == .OK {
      model.selectScanTarget(panel.url)
    }
  }

  private func returnToSetup() {
    model.cancelScan()
    model.selectScanTarget(nil)
    withAnimation {
      stage = .setup
    }
  }

  private func startMacintoshHDScanFlow() {
    if hasAcknowledgedDiskScanDisclosure {
      beginFullDiskScan()
      return
    }
    showFullDiskScanDisclosure = true
  }

  private func beginFullDiskScan() {
    withAnimation {
      stage = .session
    }
    model.scanMacintoshHD()
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

        Text("LunarDisk reads metadata only, not file contents.")
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
          beginFullDiskScan()
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
