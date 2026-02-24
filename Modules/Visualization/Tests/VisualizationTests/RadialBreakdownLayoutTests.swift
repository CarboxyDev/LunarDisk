import CoreScan
import XCTest
@testable import Visualization

final class RadialBreakdownLayoutTests: XCTestCase {
  func testFirstLevelArcsCoverFullCircle() {
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

    let arcs = RadialBreakdownLayout.makeArcs(from: root)
    let firstLevel = arcs.filter { $0.depth == 1 }
    let span = firstLevel.reduce(0.0) { partialResult, arc in
      partialResult + (arc.endAngle - arc.startAngle)
    }

    XCTAssertEqual(firstLevel.count, 2)
    XCTAssertEqual(span, 2 * .pi, accuracy: 0.0001)
  }

  func testSmallChildrenAreCollapsedIntoAggregateArc() {
    let children = [
      FileNode(name: "a", path: "/root/a", isDirectory: false, sizeBytes: 70),
      FileNode(name: "b", path: "/root/b", isDirectory: false, sizeBytes: 15),
      FileNode(name: "c", path: "/root/c", isDirectory: false, sizeBytes: 5),
      FileNode(name: "d", path: "/root/d", isDirectory: false, sizeBytes: 5),
      FileNode(name: "e", path: "/root/e", isDirectory: false, sizeBytes: 5)
    ]
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 100,
      children: children
    )

    let arcs = RadialBreakdownLayout.makeArcs(
      from: root,
      maxDepth: 4,
      maxChildrenPerNode: 2,
      minVisibleFraction: 0.11
    )
    let firstLevel = arcs.filter { $0.depth == 1 }
    let aggregate = firstLevel.first { $0.isAggregate }

    XCTAssertNotNil(aggregate)
    XCTAssertEqual(firstLevel.count, 3)
    XCTAssertEqual(aggregate?.sizeBytes, 15)
  }
}
