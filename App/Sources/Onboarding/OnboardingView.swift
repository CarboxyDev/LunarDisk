import SwiftUI

private struct OnboardingStep: Identifiable {
  let id: Int
  let title: String
  let subtitle: String
  let points: [String]
  let systemImage: String
}

struct OnboardingView: View {
  let onFinish: () -> Void

  @State private var selectedStep = 0

  private let steps: [OnboardingStep] = [
    OnboardingStep(
      id: 0,
      title: "Choose What to Scan",
      subtitle: "Run a full-disk scan or focus on one folder.",
      points: [
        "Use Full-Disk Scan for a complete storage map.",
        "Pick a folder when you want a focused, faster pass.",
        "Cancel any scan and rerun after cleanup."
      ],
      systemImage: "folder.fill"
    ),
    OnboardingStep(
      id: 1,
      title: "Understand Storage Quickly",
      subtitle: "See where space is going without manual digging.",
      points: [
        "Treemap highlights the biggest storage areas first.",
        "Top Items supports both direct and deep views.",
        "Insights help you prioritize high-impact cleanup."
      ],
      systemImage: "chart.pie.fill"
    ),
    OnboardingStep(
      id: 2,
      title: "Privacy First, Always Local",
      subtitle: "Your scan data stays on your Mac.",
      points: [
        "LunarDisk reads metadata only: names, paths, structure, and sizes.",
        "File contents are never uploaded or stored by the app.",
        "Only required access is requested, with recovery guidance if blocked."
      ],
      systemImage: "lock.shield.fill"
    ),
  ]

  var body: some View {
    ZStack {
      background
      content
    }
  }

  private var background: some View {
    AppTheme.Colors.background.ignoresSafeArea()
  }

  private var content: some View {
    VStack(spacing: AppTheme.Metrics.sectionSpacing) {
      header

      ZStack {
        ForEach(steps) { step in
          if step.id == selectedStep {
            OnboardingStepCard(
              step: step
            )
            .transition(
              .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
              )
            )
          }
        }
      }
      .frame(maxHeight: 420)
      .animation(.spring(response: 0.32, dampingFraction: 0.9), value: selectedStep)

      controls
    }
    .frame(maxWidth: AppTheme.Metrics.containerMaxWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.horizontal, 28)
    .padding(.vertical, AppTheme.Metrics.onboardingVerticalPadding)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      LunarAppIcon(size: .hero)

      VStack(alignment: .leading, spacing: AppTheme.Metrics.titleSpacing) {
        Text("LunarDisk")
          .font(AppTheme.Typography.heroTitle)
          .foregroundStyle(AppTheme.Colors.textPrimary)

        Text("Local disk usage analysis for macOS")
          .font(AppTheme.Typography.heroSubtitle)
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }
    }
  }

  private var controls: some View {
    VStack(spacing: 14) {
      HStack(spacing: 8) {
        ForEach(steps) { step in
          Capsule()
            .fill(step.id == selectedStep ? AppTheme.Colors.stepIndicatorActive : AppTheme.Colors.stepIndicatorInactive)
            .frame(
              width: step.id == selectedStep ? AppTheme.Metrics.indicatorActiveWidth : AppTheme.Metrics.indicatorWidth,
              height: AppTheme.Metrics.indicatorHeight
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedStep)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        if selectedStep > 0 {
          Button("Back") {
            withAnimation {
              selectedStep -= 1
            }
          }
          .buttonStyle(LunarSecondaryButtonStyle())
        }

        Spacer()

        Button(selectedStep == steps.count - 1 ? "Start Scanning" : "Next") {
          withAnimation {
            if selectedStep == steps.count - 1 {
              onFinish()
            } else {
              selectedStep += 1
            }
          }
        }
        .buttonStyle(LunarPrimaryButtonStyle())
      }
      .padding(.horizontal, AppTheme.Metrics.controlHorizontalPadding)
    }
  }
}

private struct OnboardingStepCard: View {
  let step: OnboardingStep

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Metrics.cardSpacing) {
      HStack(alignment: .center) {
        Image(systemName: step.systemImage)
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(AppTheme.Colors.accent)
          .padding(11)
          .background(
            Circle()
              .fill(AppTheme.Colors.surfaceElevated)
          )
          .shadow(color: AppTheme.Colors.shadow, radius: 6, x: 0, y: 2)

        Spacer()
      }

      Text(step.title)
        .font(AppTheme.Typography.cardTitle)
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text(step.subtitle)
        .font(AppTheme.Typography.cardSubtitle)
        .foregroundStyle(AppTheme.Colors.textSecondary)

      Divider()
        .overlay(AppTheme.Colors.divider)
        .frame(height: AppTheme.Metrics.dividerHeight)

      VStack(alignment: .leading, spacing: 10) {
        ForEach(step.points, id: \.self) { point in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
              .fill(AppTheme.Colors.textTertiary)
              .frame(width: 4, height: 4)
              .offset(y: -1)

            Text(point)
              .font(AppTheme.Typography.body)
              .foregroundStyle(AppTheme.Colors.textSecondary)
              .lineLimit(nil)
          }
        }
      }

      Spacer()
    }
    .padding(AppTheme.Metrics.cardPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
        .fill(AppTheme.Colors.surface)
        .overlay(
          RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
            .stroke(
              AppTheme.Colors.cardBorder,
              lineWidth: AppTheme.Metrics.cardBorderWidth
            )
        )
        .shadow(color: AppTheme.Colors.shadow, radius: 20, x: 0, y: 12)
    )
  }
}
