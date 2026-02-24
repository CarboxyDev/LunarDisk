import Foundation

public struct RadialBreakdownArc: Identifiable, Hashable, Sendable {
  public let id: String
  public let parentID: String?
  public let startAngle: Double
  public let endAngle: Double
  public let depth: Int
  public let sizeBytes: Int64
  public let label: String
  public let path: String?
  public let isDirectory: Bool
  public let isAggregate: Bool
  public let branchIndex: Int

  public var span: Double {
    max(0, endAngle - startAngle)
  }

  public init(
    id: String,
    parentID: String?,
    startAngle: Double,
    endAngle: Double,
    depth: Int,
    sizeBytes: Int64,
    label: String,
    path: String?,
    isDirectory: Bool,
    isAggregate: Bool,
    branchIndex: Int
  ) {
    self.id = id
    self.parentID = parentID
    self.startAngle = startAngle
    self.endAngle = endAngle
    self.depth = depth
    self.sizeBytes = sizeBytes
    self.label = label
    self.path = path
    self.isDirectory = isDirectory
    self.isAggregate = isAggregate
    self.branchIndex = branchIndex
  }
}
