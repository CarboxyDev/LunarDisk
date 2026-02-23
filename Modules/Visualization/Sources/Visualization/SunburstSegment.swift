import Foundation

public struct SunburstSegment: Identifiable, Hashable, Sendable {
  public let id: String
  public let startAngle: Double
  public let endAngle: Double
  public let depth: Int
  public let sizeBytes: Int64
  public let label: String

  public init(
    id: String,
    startAngle: Double,
    endAngle: Double,
    depth: Int,
    sizeBytes: Int64,
    label: String
  ) {
    self.id = id
    self.startAngle = startAngle
    self.endAngle = endAngle
    self.depth = depth
    self.sizeBytes = sizeBytes
    self.label = label
  }
}

