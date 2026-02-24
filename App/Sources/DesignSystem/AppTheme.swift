import AppKit
import SwiftUI

private typealias RGB = (red: Double, green: Double, blue: Double)

private extension Color {
  static func dynamic(light: RGB, dark: RGB) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resolved = isDark ? dark : light
        return NSColor(
          calibratedRed: resolved.red / 255,
          green: resolved.green / 255,
          blue: resolved.blue / 255,
          alpha: 1
        )
      }
    )
  }
}

enum AppTheme {
  enum Colors {
    static let background = Color.dynamic(light: (248, 247, 250), dark: (26, 24, 35))
    static let surface = Color.dynamic(light: (255, 255, 255), dark: (35, 32, 48))
    static let surfaceElevated = Color.dynamic(light: (234, 231, 240), dark: (42, 39, 58))
    static let surfaceBorder = Color.dynamic(light: (206, 201, 217), dark: (48, 44, 64))

    static let textPrimary = Color.dynamic(light: (61, 60, 79), dark: (224, 221, 239))
    static let textSecondary = Color.dynamic(light: (107, 104, 128), dark: (160, 154, 173))
    static let textTertiary = textSecondary.opacity(0.82)

    static let accent = Color.dynamic(light: (138, 121, 171), dark: (169, 149, 201))
    static let accentForeground = Color.dynamic(light: (248, 247, 250), dark: (26, 24, 35))
    static let destructive = Color.dynamic(light: (217, 92, 92), dark: (229, 115, 115))
    static let destructiveForeground = Color.dynamic(light: (248, 247, 250), dark: (26, 24, 35))

    static let chart1 = Color.dynamic(light: (138, 121, 171), dark: (169, 149, 201))
    static let chart2 = Color.dynamic(light: (230, 165, 184), dark: (242, 184, 198))
    static let chart3 = Color.dynamic(light: (119, 184, 161), dark: (119, 184, 161))
    static let chart4 = Color.dynamic(light: (240, 200, 141), dark: (240, 200, 141))
    static let chart5 = Color.dynamic(light: (160, 187, 227), dark: (160, 187, 227))
    static let chartPalette = [chart1, chart2, chart3, chart4, chart5]

    static let statusSuccessForeground = Color.dynamic(light: (49, 92, 78), dark: (171, 220, 203))
    static let statusSuccessBackground = Color.dynamic(light: (221, 239, 232), dark: (38, 55, 50))
    static let statusSuccessBorder = Color.dynamic(light: (168, 208, 193), dark: (73, 111, 101))

    static let statusWarningForeground = Color.dynamic(light: (99, 71, 33), dark: (244, 209, 157))
    static let statusWarningBackground = Color.dynamic(light: (247, 233, 207), dark: (68, 54, 35))
    static let statusWarningBorder = Color.dynamic(light: (225, 185, 121), dark: (140, 110, 68))

    static let appBackgroundGradientStart = surfaceElevated.opacity(0.3)
    static let appBackgroundGradientEnd = background.opacity(0.9)
    static let statusScanningBackground = surfaceElevated.opacity(0.8)
    static let statusIdleBackground = surfaceElevated.opacity(0.7)
    static let targetBannerBackground = surfaceElevated.opacity(0.55)
    static let failureBannerBackground = surfaceElevated.opacity(0.75)
    static let disclosureCalloutBackground = surfaceElevated.opacity(0.55)
    static let permissionStepBadgeBackground = accent.opacity(0.95)
    static let scanningSkeleton = surfaceElevated.opacity(0.7)
    static let scanningGlyphBackground = surfaceElevated.opacity(0.45)
    static let scanningGlyphRing = textSecondary.opacity(0.9)
    static let shimmerHighlight = Color.white.opacity(0.34)
    static let sheetIconShadow = shadow.opacity(0.7)

    static let primaryButtonFillPressed = accent.opacity(0.84)
    static let secondaryButtonFillRest = surfaceElevated.opacity(0.82)
    static let secondaryButtonFillPressed = surfaceElevated.opacity(0.95)

    static let stepIndicatorActive = accent
    static let stepIndicatorInactive = surfaceBorder
    static let divider = surfaceBorder.opacity(0.52)
    static let cardBorder = surfaceBorder.opacity(0.7)
    static let shadow = Color.black.opacity(0.18)
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
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(
      cornerRadius: AppTheme.Metrics.buttonCornerRadius,
      style: .continuous
    )

    configuration.label
      .font(AppTheme.Typography.button)
      .foregroundStyle(AppTheme.Colors.accentForeground)
      .frame(minWidth: AppTheme.Metrics.buttonMinWidth)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        shape
          .fill(configuration.isPressed ? AppTheme.Colors.primaryButtonFillPressed : AppTheme.Colors.accent)
      )
      .opacity(isEnabled ? 1 : 0.45)
      .contentShape(shape)
      .clipShape(shape)
      .focusEffectDisabled()
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct LunarSecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(
      cornerRadius: AppTheme.Metrics.buttonCornerRadius,
      style: .continuous
    )

    configuration.label
      .font(AppTheme.Typography.button)
      .foregroundStyle(AppTheme.Colors.textPrimary)
      .frame(minWidth: AppTheme.Metrics.buttonMinWidth)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        shape
          .fill(configuration.isPressed ? AppTheme.Colors.secondaryButtonFillPressed : AppTheme.Colors.secondaryButtonFillRest)
          .overlay(
            shape
              .stroke(AppTheme.Colors.surfaceBorder, lineWidth: 1)
          )
      )
      .opacity(isEnabled ? 1 : 0.45)
      .contentShape(shape)
      .clipShape(shape)
      .focusEffectDisabled()
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct LunarDestructiveButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(
      cornerRadius: AppTheme.Metrics.buttonCornerRadius,
      style: .continuous
    )

    configuration.label
      .font(AppTheme.Typography.button)
      .foregroundStyle(AppTheme.Colors.destructiveForeground)
      .frame(minWidth: AppTheme.Metrics.buttonMinWidth)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        shape
          .fill(configuration.isPressed ? AppTheme.Colors.destructive.opacity(0.84) : AppTheme.Colors.destructive)
      )
      .opacity(isEnabled ? 1 : 0.45)
      .contentShape(shape)
      .clipShape(shape)
      .focusEffectDisabled()
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
