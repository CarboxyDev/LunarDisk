import Foundation

public struct RadialBreakdownInspectorChild: Identifiable, Hashable, Sendable {
  public let id: String
  public let label: String
  public let sizeBytes: Int64?
  public let symbolName: String
  public let isMuted: Bool

  public init(
    id: String,
    label: String,
    sizeBytes: Int64?,
    symbolName: String,
    isMuted: Bool
  ) {
    self.id = id
    self.label = label
    self.sizeBytes = sizeBytes
    self.symbolName = symbolName
    self.isMuted = isMuted
  }
}

public struct RadialBreakdownInspectorSnapshot: Identifiable, Hashable, Sendable {
  public let id: String
  public let label: String
  public let path: String?
  public let sizeBytes: Int64
  public let shareOfRoot: Double
  public let symbolName: String
  public let isDirectory: Bool
  public let isAggregate: Bool
  public let children: [RadialBreakdownInspectorChild]

  public init(
    id: String,
    label: String,
    path: String?,
    sizeBytes: Int64,
    shareOfRoot: Double,
    symbolName: String,
    isDirectory: Bool,
    isAggregate: Bool,
    children: [RadialBreakdownInspectorChild]
  ) {
    self.id = id
    self.label = label
    self.path = path
    self.sizeBytes = sizeBytes
    self.shareOfRoot = shareOfRoot
    self.symbolName = symbolName
    self.isDirectory = isDirectory
    self.isAggregate = isAggregate
    self.children = children
  }
}
