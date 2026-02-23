import Foundation

public enum InsightSeverity: String, Sendable {
  case info
  case warning
}

public struct Insight: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let severity: InsightSeverity
  public let message: String

  public init(id: UUID = UUID(), severity: InsightSeverity, message: String) {
    self.id = id
    self.severity = severity
    self.message = message
  }
}

