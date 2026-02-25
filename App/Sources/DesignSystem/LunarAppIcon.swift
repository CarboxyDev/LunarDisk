import SwiftUI

struct LunarAppIcon: View {
  enum Size {
    case hero
    case section

    var assetName: String {
      switch self {
      case .hero:
        return "BrandIconHero"
      case .section:
        return "BrandIconSection"
      }
    }

    var dimension: CGFloat {
      switch self {
      case .hero:
        return 60
      case .section:
        return 32
      }
    }

    var shadowRadius: CGFloat {
      switch self {
      case .hero:
        return 10
      case .section:
        return 4
      }
    }

    var shadowYOffset: CGFloat {
      switch self {
      case .hero:
        return 3
      case .section:
        return 1
      }
    }

    var cornerRadius: CGFloat {
      dimension * 0.22
    }
  }

  let size: Size

  var body: some View {
    Image(size.assetName)
      .resizable()
      .interpolation(.high)
      .antialiased(true)
      .frame(width: size.dimension, height: size.dimension)
      .clipShape(
        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
      )
      .shadow(
        color: AppTheme.Colors.shadow.opacity(0.55),
        radius: size.shadowRadius,
        x: 0,
        y: size.shadowYOffset
      )
      .accessibilityHidden(true)
  }
}
