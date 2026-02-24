import CoreGraphics
import Foundation

public struct TreemapCell: Identifiable, Hashable, Sendable {
  public let id: String
  public let rect: CGRect
  public let depth: Int
  public let sizeBytes: Int64
  public let label: String
  public let path: String?
  public let isDirectory: Bool
  public let isAggregate: Bool

  public init(
    id: String,
    rect: CGRect,
    depth: Int,
    sizeBytes: Int64,
    label: String,
    path: String?,
    isDirectory: Bool,
    isAggregate: Bool
  ) {
    self.id = id
    self.rect = rect
    self.depth = depth
    self.sizeBytes = sizeBytes
    self.label = label
    self.path = path
    self.isDirectory = isDirectory
    self.isAggregate = isAggregate
  }
}
