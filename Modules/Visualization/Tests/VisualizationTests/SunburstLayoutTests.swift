import CoreScan
import XCTest
@testable import Visualization

final class SunburstLayoutTests: XCTestCase {
  func testFirstLevelSegmentsCoverFullCircle() {
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 100,
      children: [
        FileNode(name: "a", path: "/root/a", isDirectory: false, sizeBytes: 70),
        FileNode(name: "b", path: "/root/b", isDirectory: false, sizeBytes: 30)
      ]
    )

    let segments = SunburstLayout.makeSegments(from: root)
    let levelOneSegments = segments.filter { $0.depth == 1 }
    let totalSpan = levelOneSegments.reduce(0.0) { partialResult, segment in
      partialResult + (segment.endAngle - segment.startAngle)
    }

    XCTAssertEqual(levelOneSegments.count, 2)
    XCTAssertEqual(totalSpan, 2 * .pi, accuracy: 0.0001)
  }
}

