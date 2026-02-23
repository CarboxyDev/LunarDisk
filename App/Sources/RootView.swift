import AppKit
import CoreScan
import LunardiskAI
import SwiftUI
import Visualization

struct RootView: View {
  @EnvironmentObject private var onboardingState: OnboardingStateStore
  @StateObject private var model = AppModel()

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
      AppTheme.Colors.background.ignoresSafeArea()

      VStack(alignment: .leading, spacing: 16) {
        controls
        content
      }
      .padding(20)
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Disk Usage")
        .font(AppTheme.Typography.heroTitle)
        .foregroundStyle(AppTheme.Colors.textPrimary)

      HStack(spacing: 10) {
        Button("Choose Folder") {
          chooseFolder()
        }
        .buttonStyle(LunarSecondaryButtonStyle())

        Button("Scan") {
          model.startScan()
        }
        .buttonStyle(LunarPrimaryButtonStyle())
        .disabled(model.selectedURL == nil || model.isScanning)

        if model.isScanning {
          Button("Cancel") {
            model.cancelScan()
          }
          .buttonStyle(LunarSecondaryButtonStyle())
        }

        Spacer()
      }
      .frame(maxWidth: .infinity)

      if let selectedURL = model.selectedURL {
        Text(selectedURL.path)
          .font(.system(size: 12, weight: .regular, design: .monospaced))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .lineLimit(1)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(AppTheme.Colors.surfaceElevated.opacity(0.55))
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
              )
          )
      } else {
        Text("No folder selected")
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }
    }
    .padding(16)
    .background(panelBackground())
  }

  @ViewBuilder
  private var content: some View {
    if model.isScanning {
      loadingState
    } else if let rootNode = model.rootNode {
      resultsContent(rootNode: rootNode)
    } else if let errorMessage = model.errorMessage {
      statePanel(
        icon: "exclamationmark.triangle.fill",
        title: "Scan Failed",
        message: errorMessage
      )
    } else {
      statePanel(
        icon: "tray.fill",
        title: "Ready to Scan",
        message: "Choose a folder and run a scan to see storage breakdown."
      )
    }
  }

  private var loadingState: some View {
    statePanel(
      icon: "hourglass",
      title: "Scanning",
      message: "Reading directory sizes. You can cancel any time."
    )
    .overlay(
      ProgressView()
        .controlSize(.small)
        .tint(AppTheme.Colors.textSecondary)
        .padding(.top, 70)
    )
  }

  private func resultsContent(rootNode: FileNode) -> some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Distribution")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        SunburstChartView(root: rootNode)
          .frame(minWidth: 460, minHeight: 460)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(panelBackground())

      VStack(alignment: .leading, spacing: 16) {
        topItemsSection(rootNode: rootNode)
        insightsSection
      }
      .frame(width: 420, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
      model.selectedURL = panel.url
      model.rootNode = nil
      model.insights = []
      model.errorMessage = nil
    }
  }
}
