import SwiftUI

enum LunarSetupCardTone {
  case standard
  case emphasis
  case warning
}

private struct LunarSetupCardStyle {
  let fill: Color
  let stroke: Color
  let strokeWidth: CGFloat
}

private struct LunarSetupCardModifier: ViewModifier {
  let tone: LunarSetupCardTone
  let padding: CGFloat

  func body(content: Content) -> some View {
    let style = styleForTone(tone)

    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
          .fill(style.fill)
          .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Metrics.cardCornerRadius, style: .continuous)
              .stroke(style.stroke, lineWidth: style.strokeWidth)
          )
          .shadow(color: AppTheme.Colors.shadow, radius: 16, x: 0, y: 8)
      )
  }

  private func styleForTone(_ tone: LunarSetupCardTone) -> LunarSetupCardStyle {
    switch tone {
    case .standard:
      return LunarSetupCardStyle(
        fill: AppTheme.Colors.surface,
        stroke: AppTheme.Colors.cardBorder,
        strokeWidth: AppTheme.Metrics.cardBorderWidth
      )
    case .emphasis:
      return LunarSetupCardStyle(
        fill: AppTheme.Colors.surface,
        stroke: AppTheme.Colors.accent.opacity(0.55),
        strokeWidth: 1.1
      )
    case .warning:
      return LunarSetupCardStyle(
        fill: AppTheme.Colors.failureBannerBackground,
        stroke: AppTheme.Colors.statusWarningBorder,
        strokeWidth: 1
      )
    }
  }
}

extension View {
  func lunarSetupCard(
    tone: LunarSetupCardTone = .standard,
    padding: CGFloat = 16
  ) -> some View {
    modifier(LunarSetupCardModifier(tone: tone, padding: padding))
  }
}
