import CoreGraphics
import CoreScan
import SwiftUI

public struct SunburstChartView: View {
  private static let ringInset: CGFloat = 1
  private static let defaultPalette: [Color] = [
    Color(red: 138 / 255, green: 121 / 255, blue: 171 / 255),
    Color(red: 230 / 255, green: 165 / 255, blue: 184 / 255),
    Color(red: 119 / 255, green: 184 / 255, blue: 161 / 255),
    Color(red: 240 / 255, green: 200 / 255, blue: 141 / 255),
    Color(red: 160 / 255, green: 187 / 255, blue: 227 / 255),
  ]

  private let segments: [SunburstSegment]
  private let palette: [Color]

  public init(root: FileNode) {
    self.init(root: root, palette: Self.defaultPalette)
  }

  public init(root: FileNode, palette: [Color]) {
    self.segments = SunburstLayout.makeSegments(from: root)
    self.palette = palette.isEmpty ? Self.defaultPalette : palette
  }

  public var body: some View {
    Canvas { context, size in
      let diameter = min(size.width, size.height)
      guard diameter > 0 else { return }

      let radius = (diameter / 2) - Self.ringInset
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let maxDepth = max(segments.map(\.depth).max() ?? 1, 1)
      let bandWidth = radius / CGFloat(maxDepth + 1)

      for segment in segments where segment.depth > 0 {
        let innerRadius = CGFloat(segment.depth) * bandWidth
        let outerRadius = max(innerRadius + bandWidth - 2, innerRadius + 1)

        var path = Path()
        path.addArc(
          center: center,
          radius: outerRadius,
          startAngle: .radians(segment.startAngle),
          endAngle: .radians(segment.endAngle),
          clockwise: false
        )
        path.addArc(
          center: center,
          radius: innerRadius,
          startAngle: .radians(segment.endAngle),
          endAngle: .radians(segment.startAngle),
          clockwise: true
        )
        path.closeSubpath()

        context.fill(path, with: .color(color(for: segment)))
      }
    }
  }

  private func color(for segment: SunburstSegment) -> Color {
    let colorIndex = (abs(segment.id.hashValue) + segment.depth) % palette.count
    let opacity = max(0.62, 0.95 - (Double(segment.depth % 6) * 0.06))
    return palette[colorIndex].opacity(opacity)
  }
}
