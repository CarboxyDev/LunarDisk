import SwiftUI

struct ScanningStatePanel: View {
  let title: String
  let message: String
  let steps: [String]
  @State private var activeStepIndex = 0

  var body: some View {
    VStack(spacing: 18) {
      AnimatedScanGlyph()

      VStack(spacing: 8) {
        Text(title)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .multilineTextAlignment(.center)

        Text(message)
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: 580)

      scanLiveBadge

      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
          .tint(AppTheme.Colors.textSecondary)

        Text(activeStepText)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .lineLimit(1)
      }
      .padding(.top, 12)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 28)
    .frame(maxWidth: 780)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .lunarPanelBackground()
    .onReceive(
      Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()
    ) { _ in
      guard !steps.isEmpty else { return }
      withAnimation(.easeInOut(duration: 0.2)) {
        activeStepIndex = (activeStepIndex + 1) % steps.count
      }
    }
  }

  private var scanLiveBadge: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(AppTheme.Colors.accent)
        .frame(width: 8, height: 8)
      Text("Scan in progress")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(0.75))
        .overlay(
          Capsule(style: .continuous)
            .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
        )
    )
  }

  private var activeStepText: String {
    guard !steps.isEmpty else {
      return "Scanning…"
    }
    return steps[activeStepIndex]
  }
}

private struct AnimatedScanGlyph: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 22, style: .continuous)
      .fill(
        LinearGradient(
          colors: [
            AppTheme.Colors.scanningGlyphBackground,
            AppTheme.Colors.surfaceElevated.opacity(0.92)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
      )
      .overlay {
        Image(systemName: "internaldrive.fill")
          .font(.system(size: 31, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
      }
      .frame(width: 84, height: 84)
      .shadow(color: AppTheme.Colors.shadow, radius: 10, x: 0, y: 6)
  }
}
