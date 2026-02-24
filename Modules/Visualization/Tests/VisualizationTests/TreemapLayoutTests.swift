import CoreScan
import XCTest
@testable import Visualization

final class TreemapLayoutTests: XCTestCase {
  func testMakeCellsRespectsDepthLimit() {
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 100,
      children: [
        FileNode(
          name: "a",
          path: "/root/a",
          isDirectory: true,
          sizeBytes: 80,
          children: [
            FileNode(name: "a1", path: "/root/a/a1", isDirectory: true, sizeBytes: 60, children: [
              FileNode(name: "a1f", path: "/root/a/a1/f", isDirectory: false, sizeBytes: 60),
            ]),
          ]
        ),
        FileNode(name: "b", path: "/root/b", isDirectory: false, sizeBytes: 20),
      ]
    )

    let depthOne = TreemapLayout.makeCells(from: root, maxDepth: 1)
    XCTAssertTrue(depthOne.allSatisfy { $0.depth == 1 })

    let depthTwo = TreemapLayout.makeCells(from: root, maxDepth: 2)
    XCTAssertTrue(depthTwo.allSatisfy { $0.depth <= 2 })
    XCTAssertTrue(depthTwo.contains { $0.id == "/root/a/a1" })
  }

  func testMakeCellsStayWithinBounds() {
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 100,
      children: [
        FileNode(name: "a", path: "/root/a", isDirectory: false, sizeBytes: 70),
        FileNode(name: "b", path: "/root/b", isDirectory: false, sizeBytes: 30),
      ]
    )

    let cells = TreemapLayout.makeCells(from: root)
    XCTAssertFalse(cells.isEmpty)
    XCTAssertTrue(cells.allSatisfy { cell in
      cell.rect.minX >= 0 &&
      cell.rect.minY >= 0 &&
      cell.rect.maxX <= 1 &&
      cell.rect.maxY <= 1 &&
      cell.rect.width >= 0 &&
      cell.rect.height >= 0
    })
  }

  func testSmallItemsAreAggregatedIntoOther() {
    let children = (0..<80).map { index in
      FileNode(
        name: "f\(index)",
        path: "/root/f\(index)",
        isDirectory: false,
        sizeBytes: index == 0 ? 500 : 1
      )
    }
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 579,
      children: children
    )

    let cells = TreemapLayout.makeCells(
      from: root,
      maxDepth: 1,
      maxChildrenPerNode: 16,
      minVisibleFraction: 0.01
    )
    XCTAssertTrue(cells.contains { $0.isAggregate && $0.label == "Other" })
    XCTAssertLessThanOrEqual(cells.filter { $0.depth == 1 }.count, 17)
  }

  func testCellBudgetIsEnforced() {
    let children = (0..<60).map { index in
      FileNode(
        name: "d\(index)",
        path: "/root/d\(index)",
        isDirectory: true,
        sizeBytes: 100,
        children: [
          FileNode(
            name: "f",
            path: "/root/d\(index)/f",
            isDirectory: false,
            sizeBytes: 100
          ),
        ]
      )
    }
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 6_000,
      children: children
    )

    let cells = TreemapLayout.makeCells(
      from: root,
      maxDepth: 3,
      maxChildrenPerNode: 60,
      minVisibleFraction: 0,
      maxCellCount: 40
    )
    XCTAssertLessThanOrEqual(cells.count, 40)
  }
}
