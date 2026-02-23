import SwiftUI

enum AppTheme {
  enum Colors {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.067)   // zinc-950
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.110)      // zinc-900
    static let surfaceElevated = Color(red: 0.149, green: 0.149, blue: 0.165) // zinc-800
    static let surfaceBorder = Color(red: 0.247, green: 0.247, blue: 0.278) // zinc-700

    static let textPrimary = Color(red: 0.980, green: 0.980, blue: 0.988)   // zinc-50
    static let textSecondary = Color(red: 0.894, green: 0.894, blue: 0.914) // zinc-200
    static let textTertiary = Color(red: 0.631, green: 0.631, blue: 0.667)  // zinc-400

    static let accent = Color(red: 0.894, green: 0.894, blue: 0.914)         // zinc-200
    static let accentForeground = Color(red: 0.094, green: 0.094, blue: 0.110) // zinc-900
    static let stepIndicatorActive = accent
    static let stepIndicatorInactive = surfaceBorder
    static let divider = Color.white.opacity(0.08)
    static let cardBorder = Color.white.opacity(0.09)
    static let shadow = Color.black.opacity(0.28)
  }

  enum Typography {
    static let heroTitle = Font.system(size: 31, weight: .semibold, design: .default)
    static let heroSubtitle = Font.system(size: 14, weight: .regular, design: .default)
    static let cardTitle = Font.system(size: 24, weight: .semibold, design: .default)
    static let cardSubtitle = Font.system(size: 15, weight: .regular, design: .default)
    static let body = Font.system(size: 14, weight: .regular, design: .default)
    static let button = Font.system(size: 13, weight: .semibold, design: .default)
  }

  enum Metrics {
    static let sectionSpacing: CGFloat = 20
    static let titleSpacing: CGFloat = 6
    static let cardSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 24
    static let cardCornerRadius: CGFloat = 16
    static let controlHorizontalPadding: CGFloat = 0
    static let onboardingVerticalPadding: CGFloat = 20
    static let indicatorWidth: CGFloat = 10
    static let indicatorActiveWidth: CGFloat = 24
    static let indicatorHeight: CGFloat = 6
    static let buttonMinWidth: CGFloat = 120
    static let buttonCornerRadius: CGFloat = 10
    static let containerMaxWidth: CGFloat = 760
    static let dividerHeight: CGFloat = 0.75
    static let cardBorderWidth: CGFloat = 0.75
  }
}

struct LunarPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(AppTheme.Typography.button)
      .foregroundStyle(AppTheme.Colors.accentForeground)
      .frame(minWidth: AppTheme.Metrics.buttonMinWidth)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: AppTheme.Metrics.buttonCornerRadius, style: .continuous)
          .fill(AppTheme.Colors.accent)
          .opacity(configuration.isPressed ? 0.84 : 1)
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct LunarSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(AppTheme.Typography.button)
      .foregroundStyle(AppTheme.Colors.textPrimary)
      .frame(minWidth: AppTheme.Metrics.buttonMinWidth)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: AppTheme.Metrics.buttonCornerRadius, style: .continuous)
          .fill(AppTheme.Colors.surfaceElevated.opacity(configuration.isPressed ? 0.95 : 0.82))
          .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Metrics.buttonCornerRadius, style: .continuous)
              .stroke(AppTheme.Colors.surfaceBorder, lineWidth: 1)
          )
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
