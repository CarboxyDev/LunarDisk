import XCTest
@testable import Lunardisk

@MainActor
final class LunardiskTests: XCTestCase {
  func testInitialModelState() {
    let model = AppModel()

    XCTAssertNil(model.selectedURL)
    XCTAssertNil(model.rootNode)
    XCTAssertTrue(model.insights.isEmpty)
    XCTAssertFalse(model.isScanning)
    XCTAssertNil(model.errorMessage)
  }
}

