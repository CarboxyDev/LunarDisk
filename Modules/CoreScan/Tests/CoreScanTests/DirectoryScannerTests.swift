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
    let expected = try expectedUsage(of: [fileA, fileB])

    XCTAssertTrue(result.isDirectory)
    XCTAssertEqual(result.children.count, 2)
    XCTAssertEqual(result.sizeBytes, expected)
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
    let diagnostics = await scanner.lastScanDiagnostics()
    let expectedVisibleSize = try expectedUsage(of: [accessibleFile])

    XCTAssertEqual(result.sizeBytes, expectedVisibleSize)
    XCTAssertEqual(result.children.count, 1)
    XCTAssertEqual(result.children.first?.name, "visible.txt")
    XCTAssertTrue((diagnostics?.skippedItemCount ?? 0) >= 1)
    XCTAssertFalse((diagnostics?.sampledSkippedPaths ?? []).isEmpty)
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

  func testDepthLimitedScanCancellationRethrowsCancellationError() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    for index in 0..<80 {
      let file = root.appendingPathComponent("file-\(index).txt")
      try Data(repeating: UInt8(index % 255), count: 4).write(to: file)
    }

    let scanner = DirectoryScanner(fileManager: SlowFileManager(delay: 0.2))
    let task = Task { try await scanner.scan(at: root, maxDepth: 0) }

    try await Task.sleep(nanoseconds: 10_000_000)
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

  func testDepthLimitedScanStillAggregatesDeepNestedFileSizes() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var current = root
    for index in 0..<5 {
      let nested = current.appendingPathComponent("dir-\(index)", isDirectory: true)
      try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
      current = nested
    }

    let deepFile = current.appendingPathComponent("deep.bin")
    try Data(repeating: 0xAC, count: 11).write(to: deepFile)

    let scanner = DirectoryScanner()
    let result = try await scanner.scan(at: root, maxDepth: 2)
    let diagnostics = await scanner.lastScanDiagnostics()
    let expected = try expectedUsage(of: [deepFile])

    XCTAssertEqual(result.sizeBytes, expected)
    XCTAssertEqual(result.children.count, 1)
    XCTAssertEqual(result.children.first?.sizeBytes, expected)
    XCTAssertEqual(result.children.first?.children.count, 1)
    XCTAssertEqual(result.children.first?.children.first?.sizeBytes, expected)
    XCTAssertTrue(result.children.first?.children.first?.children.isEmpty == true)
    XCTAssertFalse(diagnostics?.isPartialResult == true)
  }

  func testScanPrefersAllocatedSizeOverLogicalSizeWhenAvailable() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sparseFile = root.appendingPathComponent("sparse.bin")
    FileManager.default.createFile(atPath: sparseFile.path, contents: Data(), attributes: nil)
    let fileHandle = try FileHandle(forWritingTo: sparseFile)
    try fileHandle.seek(toOffset: 8 * 1_024 * 1_024)
    try fileHandle.write(contentsOf: Data([0xAB]))
    try fileHandle.close()

    let values = try sparseFile.resourceValues(forKeys: [
      .fileSizeKey,
      .totalFileAllocatedSizeKey,
      .fileAllocatedSizeKey
    ])
    guard let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize else {
      throw XCTSkip("Allocated size metadata unavailable on this filesystem")
    }
    guard let logical = values.fileSize else {
      throw XCTSkip("Logical file size metadata unavailable on this filesystem")
    }
    guard allocated < logical else {
      throw XCTSkip("Filesystem did not report sparse allocation difference")
    }

    let scanner = DirectoryScanner()
    let result = try await scanner.scan(at: root, maxDepth: nil, sizeStrategy: .allocated)

    XCTAssertEqual(result.sizeBytes, Int64(allocated))
    XCTAssertEqual(result.children.count, 1)
    XCTAssertEqual(result.children.first?.sizeBytes, Int64(allocated))
    XCTAssertLessThan(result.sizeBytes, Int64(logical))
  }

  func testScanCanUseLogicalSizeStrategyWhenRequested() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sparseFile = root.appendingPathComponent("sparse-logical.bin")
    FileManager.default.createFile(atPath: sparseFile.path, contents: Data(), attributes: nil)
    let fileHandle = try FileHandle(forWritingTo: sparseFile)
    try fileHandle.seek(toOffset: 8 * 1_024 * 1_024)
    try fileHandle.write(contentsOf: Data([0xCD]))
    try fileHandle.close()

    let values = try sparseFile.resourceValues(forKeys: [
      .fileSizeKey,
      .totalFileAllocatedSizeKey,
      .fileAllocatedSizeKey
    ])
    guard let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize else {
      throw XCTSkip("Allocated size metadata unavailable on this filesystem")
    }
    guard let logical = values.fileSize else {
      throw XCTSkip("Logical file size metadata unavailable on this filesystem")
    }
    guard allocated < logical else {
      throw XCTSkip("Filesystem did not report sparse allocation difference")
    }

    let scanner = DirectoryScanner()
    let allocatedResult = try await scanner.scan(at: root, maxDepth: nil, sizeStrategy: .allocated)
    let logicalResult = try await scanner.scan(at: root, maxDepth: nil, sizeStrategy: .logical)

    XCTAssertEqual(allocatedResult.sizeBytes, Int64(allocated))
    XCTAssertEqual(logicalResult.sizeBytes, Int64(logical))
    XCTAssertGreaterThan(logicalResult.sizeBytes, allocatedResult.sizeBytes)
  }

  func testSortedChildrenBySizeBreaksTiesDeterministically() {
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 30,
      children: [
        FileNode(name: "b", path: "/root/b", isDirectory: false, sizeBytes: 10),
        FileNode(name: "a", path: "/root/a", isDirectory: false, sizeBytes: 10),
        FileNode(name: "c", path: "/root/c", isDirectory: false, sizeBytes: 10),
      ]
    )

    XCTAssertEqual(root.sortedChildrenBySize.map(\.path), ["/root/a", "/root/b", "/root/c"])
  }

  private func expectedUsage(of urls: [URL]) throws -> Int64 {
    try urls.reduce(Int64(0)) { partialResult, url in
      let values = try url.resourceValues(forKeys: [
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey
      ])
      if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
        return partialResult + Int64(allocated)
      }
      return partialResult + Int64(values.fileSize ?? 0)
    }
  }
}
