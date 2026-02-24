import SwiftUI

private struct LunarShimmerModifier: ViewModifier {
  let active: Bool
  @State private var phase: CGFloat = -1

  func body(content: Content) -> some View {
    content
      .overlay {
        if active {
          GeometryReader { proxy in
            let width = max(proxy.size.width, 120)
            LinearGradient(
              colors: [
                .clear,
                AppTheme.Colors.shimmerHighlight,
                .clear
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(width: width * 0.34)
            .blur(radius: 6)
            .offset(x: phase * (width + 120))
            .onAppear {
              phase = -1
              withAnimation(.linear(duration: 1.55).repeatForever(autoreverses: false)) {
                phase = 1
              }
            }
          }
          .allowsHitTesting(false)
          .mask(content)
        }
      }
  }
}

extension View {
  func lunarShimmer(active: Bool) -> some View {
    modifier(LunarShimmerModifier(active: active))
  }
}
