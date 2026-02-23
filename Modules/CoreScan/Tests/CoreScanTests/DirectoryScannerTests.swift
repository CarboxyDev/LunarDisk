import Foundation
import XCTest
@testable import CoreScan

final class DirectoryScannerTests: XCTestCase {
  func testScanAggregatesChildFileSizes() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let fileA = root.appendingPathComponent("a.txt")
    let fileB = root.appendingPathComponent("b.txt")
    try Data(repeating: 0x01, count: 4).write(to: fileA)
    try Data(repeating: 0x02, count: 6).write(to: fileB)

    let scanner = DirectoryScanner()
    let result = try await scanner.scan(at: root, maxDepth: nil)

    XCTAssertTrue(result.isDirectory)
    XCTAssertEqual(result.children.count, 2)
    XCTAssertEqual(result.sizeBytes, 10)
  }

  func testByteFormatterReturnsReadableString() {
    let output = ByteFormatter.string(from: 1_500_000)
    XCTAssertFalse(output.isEmpty)
  }
}

