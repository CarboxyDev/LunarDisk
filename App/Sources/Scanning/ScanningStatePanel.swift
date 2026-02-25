import CoreScan
import SwiftUI

struct ScanningStatePanel: View {
  let title: String
  let message: String
  let progress: ScanProgress?

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

      HStack(alignment: .top, spacing: 10) {
        ProgressView()
          .controlSize(.small)
          .tint(AppTheme.Colors.textSecondary)
          .padding(.top, 2)

        VStack(alignment: .leading, spacing: 3) {
          Text(progressPrimaryText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .lineLimit(1)
            .contentTransition(.numericText(countsDown: false))
            .animation(.easeOut(duration: 0.2), value: progress?.itemsScanned)

          Text(progressSecondaryText)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .frame(width: 380, alignment: .leading)
      }
      .padding(.top, 12)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 28)
    .frame(maxWidth: 780)
    .frame(maxWidth: .infinity, alignment: .center)
    .lunarPanelBackground()
  }

  private var progressPrimaryText: String {
    guard let progress else { return "Scanning…" }
    return "\(progress.itemsScanned.formatted()) items · \(ByteFormatter.string(from: progress.bytesScanned))"
  }

  private var progressSecondaryText: String {
    guard let progress else { return " " }
    return friendlyPath(progress.currentDirectory)
  }

  private func friendlyPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
      return "~" + path.dropFirst(home.count)
    }
    return path
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
