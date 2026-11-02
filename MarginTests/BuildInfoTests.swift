import XCTest
@testable import Margin

final class BuildInfoTests: XCTestCase {
    func testReadsValuesFromInfoDictionary() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "42",
            "CFBundleIdentifier": "com.example.margin",
        ])

        XCTAssertEqual(info.version, "0.1.0")
        XCTAssertEqual(info.build, "42")
        XCTAssertEqual(info.bundleID, "com.example.margin")
        XCTAssertEqual(info.displayVersion, "0.1.0 (build 42)")
    }

    func testFallsBackWhenValuesAreMissing() {
        let info = BuildInfo(infoDictionary: nil)

        XCTAssertEqual(info.version, BuildInfo.missing)
        XCTAssertEqual(info.build, BuildInfo.missing)
        XCTAssertEqual(info.bundleID, BuildInfo.missing)
    }

    func testRunningAppHasAVersion() {
        // Unit tests run inside the app, so Bundle.main is Margin itself.
        XCTAssertNotEqual(BuildInfo.current.version, BuildInfo.missing)
        XCTAssertNotEqual(BuildInfo.current.build, BuildInfo.missing)
    }
}
