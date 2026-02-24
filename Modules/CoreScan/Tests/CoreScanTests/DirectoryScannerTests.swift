import Foundation
import XCTest
@testable import CoreScan

final class DirectoryScannerTests: XCTestCase {
  final class SlowFileManager: FileManager, @unchecked Sendable {
    private let delay: TimeInterval

    init(delay: TimeInterval) {
      self.delay = delay
      super.init()
    }

    override func contentsOfDirectory(
      at url: URL,
      includingPropertiesForKeys keys: [URLResourceKey]?,
      options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
      Thread.sleep(forTimeInterval: delay)
      return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
  }

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

  func testScanMissingPathThrowsNotFound() async {
    let missing = URL(fileURLWithPath: "/tmp/lunardisk-")
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let scanner = DirectoryScanner()

    do {
      _ = try await scanner.scan(at: missing, maxDepth: nil)
      XCTFail("Expected notFound error")
    } catch let ScanError.notFound(path) {
      XCTAssertEqual(path, missing.path)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testScanSkipsUnreadableChildDirectory() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let accessibleFile = root.appendingPathComponent("visible.txt")
    try Data(repeating: 0x01, count: 5).write(to: accessibleFile)

    let restrictedDir = root.appendingPathComponent("restricted", isDirectory: true)
    try FileManager.default.createDirectory(at: restrictedDir, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: restrictedDir.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restrictedDir.path)
    }

    let scanner = DirectoryScanner()
    let result = try await scanner.scan(at: root, maxDepth: nil)

    XCTAssertEqual(result.sizeBytes, 5)
    XCTAssertEqual(result.children.count, 1)
    XCTAssertEqual(result.children.first?.name, "visible.txt")
  }

  func testScanCancellationThrowsCancellationError() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var current = root
    for index in 0..<90 {
      let nestedDir = current.appendingPathComponent("dir-\(index)", isDirectory: true)
      try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
      let file = nestedDir.appendingPathComponent("file-\(index).txt")
      try Data(repeating: UInt8(index % 255), count: 1).write(to: file)
      current = nestedDir
    }

    let scanner = DirectoryScanner(fileManager: SlowFileManager(delay: 0.01))
    let task = Task { try await scanner.scan(at: root, maxDepth: nil) }

    try await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation error")
    } catch is CancellationError {
      XCTAssertTrue(task.isCancelled)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
