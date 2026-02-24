import CoreGraphics
import CoreScan
import SwiftUI

public struct SunburstChartView: View {
  private static let ringInset: CGFloat = 1
  private let segments: [SunburstSegment]

  public init(root: FileNode) {
    segments = SunburstLayout.makeSegments(from: root)
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
    let hue = Double(abs(segment.id.hashValue % 360)) / 360
    let saturation = min(0.55 + (Double(segment.depth % 4) * 0.08), 0.9)
    return Color(hue: hue, saturation: saturation, brightness: 0.88)
  }
}
