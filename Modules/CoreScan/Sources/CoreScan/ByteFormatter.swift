import Foundation

public enum ByteFormatter {
  public static func string(from bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytes)
  }
}

