import XCTest
import SnapshotTesting
import SnapshotReportTesting
@testable import ExampleUIKitScreens

final class UIKitSnapshotsTests: XCTestCase {
    private func reportOutputPath() -> String {
        let env = ProcessInfo.processInfo.environment
        let outputDir = env["SNAPSHOT_REPORT_OUTPUT_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(FileManager.default.currentDirectoryPath)/.artifacts/snapshot-runs-pass"
        let filename = "UIKit-Example-Snapshots-\(ProcessInfo.processInfo.processIdentifier).json"
        return URL(fileURLWithPath: outputDir).appendingPathComponent(filename).path
    }

    override func setUp() {
        super.setUp()
        configureSnapshotReport(reportName: "UIKit Example Snapshots", outputJSONPath: reportOutputPath())
        let runtimeMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        configureSnapshotAssertionDefaults(
            .init(device: .iPhone13, configuredOSMajorVersion: runtimeMajor, captureHeight: .device, highContrastReport: false)
        )
    }

    func testUIKitDemoScreens() {
        let shouldRecord = true
        for screen in UIKitDemoScreen.allCases {
            let viewController = UIKitScreenFactory.make(screen)
            let failures = assertSnapshot(
                of: viewController,
                named: screen.rawValue,
                record: shouldRecord,
                missingReferencePolicy: .recordOnMissingReference
            )
            XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        }
    }
}
