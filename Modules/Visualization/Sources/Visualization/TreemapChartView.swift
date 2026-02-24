import CoreGraphics
import CoreScan
import SwiftUI

public struct TreemapChartView: View {
  private static let defaultPalette: [Color] = [
    Color(red: 138 / 255, green: 121 / 255, blue: 171 / 255),
    Color(red: 230 / 255, green: 165 / 255, blue: 184 / 255),
    Color(red: 119 / 255, green: 184 / 255, blue: 161 / 255),
    Color(red: 240 / 255, green: 200 / 255, blue: 141 / 255),
    Color(red: 160 / 255, green: 187 / 255, blue: 227 / 255),
  ]

  private let rootSizeBytes: Int64
  private let cells: [TreemapCell]
  private let hitTestCells: [TreemapCell]
  private let cellsByID: [String: TreemapCell]
  private let palette: [Color]

  @State private var hoveredCellID: String?
  @State private var pinnedCellID: String?

  public init(root: FileNode) {
    self.init(root: root, palette: Self.defaultPalette)
  }

  public init(root: FileNode, palette: [Color]) {
    let cells = TreemapLayout.makeCells(
      from: root,
      maxDepth: 2,
      maxChildrenPerNode: 18,
      minVisibleFraction: 0.008,
      maxCellCount: 900
    )
    rootSizeBytes = root.sizeBytes
    self.cells = cells
    hitTestCells = cells.sorted { lhs, rhs in
      if lhs.depth == rhs.depth {
        return lhs.rect.width * lhs.rect.height < rhs.rect.width * rhs.rect.height
      }
      return lhs.depth > rhs.depth
    }
    cellsByID = Dictionary(uniqueKeysWithValues: cells.map { ($0.id, $0) })
    self.palette = palette.isEmpty ? Self.defaultPalette : palette
  }

  public var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let selectedCell = currentCell

      ZStack(alignment: .bottomLeading) {
        Canvas { context, canvasSize in
          for cell in cells {
            drawCell(
              cell,
              in: canvasSize,
              isSelected: selectedCell?.id == cell.id,
              context: &context
            )
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        if let selectedCell {
          selectionBadge(for: selectedCell)
            .padding(12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
          Text("Hover to inspect • Click to pin")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .padding(12)
            .transition(.opacity)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture()
          .onEnded { event in
            let hitCell = hitTest(at: event.location, in: size)
            if pinnedCellID == hitCell?.id {
              pinnedCellID = nil
            } else {
              pinnedCellID = hitCell?.id
            }
          }
      )
      .onContinuousHover { phase in
        switch phase {
        case let .active(location):
          hoveredCellID = hitTest(at: location, in: size)?.id
        case .ended:
          hoveredCellID = nil
        }
      }
      .animation(.easeInOut(duration: 0.12), value: hoveredCellID)
      .animation(.easeInOut(duration: 0.16), value: pinnedCellID)
    }
  }

  private var currentCell: TreemapCell? {
    if let pinnedCellID, let pinned = cellsByID[pinnedCellID] {
      return pinned
    }
    if let hoveredCellID, let hovered = cellsByID[hoveredCellID] {
      return hovered
    }
    return nil
  }

  private func hitTest(at point: CGPoint, in size: CGSize) -> TreemapCell? {
    guard size.width > 0, size.height > 0 else { return nil }
    let normalizedPoint = CGPoint(
      x: point.x / size.width,
      y: point.y / size.height
    )

    for cell in hitTestCells where cell.rect.contains(normalizedPoint) {
      return cell
    }

    return nil
  }

  private func drawCell(
    _ cell: TreemapCell,
    in size: CGSize,
    isSelected: Bool,
    context: inout GraphicsContext
  ) {
    let rect = denormalizedRect(from: cell.rect, in: size)
    guard rect.width > 1, rect.height > 1 else { return }

    let cornerRadius = max(2, min(min(rect.width, rect.height) * 0.09, 8))
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let insetRect = rect.insetBy(dx: 0.8, dy: 0.8)
    guard insetRect.width > 0, insetRect.height > 0 else { return }
    let path = shape.path(in: insetRect)

    let fill = color(for: cell, isSelected: isSelected)
    context.fill(
      path,
      with: .linearGradient(
        Gradient(colors: [fill, fill.opacity(0.78)]),
        startPoint: CGPoint(x: insetRect.minX, y: insetRect.minY),
        endPoint: CGPoint(x: insetRect.maxX, y: insetRect.maxY)
      )
    )

    let borderColor = isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.26)
    context.stroke(path, with: .color(borderColor), lineWidth: isSelected ? 2 : 0.8)

    if insetRect.width > 84, insetRect.height > 22 {
      let labelText = (cell.isAggregate ? Text("Other") : Text(cell.label))
        .font(.system(size: 10.5, weight: .semibold))
      var resolved = context.resolve(labelText)
      resolved.shading = .color(.primary.opacity(0.96))
      context.draw(
        resolved,
        at: CGPoint(x: insetRect.minX + 6, y: insetRect.minY + 5),
        anchor: .topLeading
      )
    }
  }

  private func denormalizedRect(from rect: CGRect, in size: CGSize) -> CGRect {
    CGRect(
      x: rect.minX * size.width,
      y: rect.minY * size.height,
      width: rect.width * size.width,
      height: rect.height * size.height
    )
  }

  private func color(for cell: TreemapCell, isSelected: Bool) -> Color {
    let colorIndex = (abs(cell.id.hashValue) + cell.depth) % palette.count
    let baseOpacity = max(0.82, 0.97 - (Double(cell.depth % 6) * 0.04))
    let selectedBoost = isSelected ? 0.08 : 0
    return palette[colorIndex].opacity(min(baseOpacity + selectedBoost, 1))
  }

  private func selectionBadge(for cell: TreemapCell) -> some View {
    let ratio = Double(cell.sizeBytes) / Double(max(rootSizeBytes, 1))
    let percentage = ratio * 100

    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: badgeIcon(for: cell))
          .font(.system(size: 11, weight: .semibold))
        Text(cell.label)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
      }
      .foregroundStyle(Color.primary)

      Text("\(ByteFormatter.string(from: cell.sizeBytes)) • \(String(format: "%.1f", percentage))%")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.82))
        .lineLimit(1)

      if let path = cell.path, !path.isEmpty {
        Text(path)
          .font(.system(size: 10, weight: .regular, design: .monospaced))
          .foregroundStyle(Color.primary.opacity(0.72))
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
    )
    .frame(maxWidth: 420, alignment: .leading)
  }

  private func badgeIcon(for cell: TreemapCell) -> String {
    if cell.isAggregate {
      return "square.grid.3x3.fill"
    }
    return cell.isDirectory ? "folder.fill" : "doc.fill"
  }
}
