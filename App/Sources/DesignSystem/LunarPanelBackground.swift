import SwiftUI

struct LunarPanelBackground: View {
  var body: some View {
    RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
      .fill(AppTheme.Colors.surface)
      .overlay(
        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
          .stroke(AppTheme.Colors.cardBorder, lineWidth: AppTheme.Metrics.cardBorderWidth)
      )
      .shadow(color: AppTheme.Colors.shadow, radius: 16, x: 0, y: 8)
  }
}

extension View {
  func lunarPanelBackground() -> some View {
    background(LunarPanelBackground())
  }
}
