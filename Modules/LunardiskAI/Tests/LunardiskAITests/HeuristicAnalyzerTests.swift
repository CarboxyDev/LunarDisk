import CoreScan
import XCTest
@testable import LunardiskAI

final class HeuristicAnalyzerTests: XCTestCase {
  func testAnalyzerFlagsDominantDirectory() async {
    let root = FileNode(
      name: "root",
      path: "/root",
      isDirectory: true,
      sizeBytes: 100,
      children: [
        FileNode(name: "huge", path: "/root/huge", isDirectory: false, sizeBytes: 90),
        FileNode(name: "small", path: "/root/small", isDirectory: false, sizeBytes: 10)
      ]
    )

    let analyzer = HeuristicAnalyzer()
    let insights = await analyzer.generateInsights(for: root)

    XCTAssertTrue(insights.contains { $0.message.contains("90%") })
    XCTAssertTrue(insights.contains { $0.severity == .warning })
  }
}

