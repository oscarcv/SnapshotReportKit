import Foundation
import Testing
@testable import SnapshotReportCore

@Test
func mergeAggregatesSuitesAndCounts() {
    let reportA = SnapshotReport(
        name: "A",
        suites: [
            SnapshotSuite(name: "SuiteOne", tests: [
                SnapshotTestCase(name: "testPass", className: "SuiteOneTests", status: .passed, duration: 0.1)
            ])
        ]
    )

    let reportB = SnapshotReport(
        name: "B",
        suites: [
            SnapshotSuite(name: "SuiteOne", tests: [
                SnapshotTestCase(name: "testFail", className: "SuiteOneTests", status: .failed, duration: 0.2)
            ]),
            SnapshotSuite(name: "SuiteTwo", tests: [
                SnapshotTestCase(name: "testSkip", className: "SuiteTwoTests", status: .skipped, duration: 0.0)
            ])
        ]
    )

    let merged = SnapshotReportAggregator.merge(reports: [reportA, reportB], name: "Merged")

    #expect(merged.name == "Merged")
    #expect(merged.suites.count == 2)
    #expect(merged.summary.total == 3)
    #expect(merged.summary.passed == 1)
    #expect(merged.summary.failed == 1)
    #expect(merged.summary.skipped == 1)
}

@Test
func junitRendererIncludesAttachments() {
    let report = SnapshotReport(
        name: "Snapshots",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(
                    name: "testSnapshot",
                    className: "SuiteTests",
                    status: .failed,
                    duration: 0.3,
                    failure: SnapshotFailure(message: "diff"),
                    attachments: [
                        SnapshotAttachment(name: "Reference", type: .png, path: "/tmp/ref.png")
                    ]
                )
            ])
        ]
    )

    let xml = JUnitXMLRenderer().render(report: report)

    #expect(xml.contains("<attachments>"))
    #expect(xml.contains("type=\"image/png\""))
    #expect(xml.contains("<system-out>"))
}

@Test
func writersUseReporterImplementations() throws {
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotReportCoreTests-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    defer {
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    let report = SnapshotReport(
        name: "Writers",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(name: "test", className: "SuiteTests", status: .passed, duration: 0.05)
            ])
        ]
    )

    try SnapshotReportWriters.write(report, format: .json, options: .init(outputDirectory: outputDirectory))
    try SnapshotReportWriters.write(report, format: .junit, options: .init(outputDirectory: outputDirectory))
    try SnapshotReportWriters.write(report, format: .html, options: .init(outputDirectory: outputDirectory))

    #expect(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("report.json").path))
    #expect(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("report.junit.xml").path))
    #expect(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("html/index.html").path))
}
