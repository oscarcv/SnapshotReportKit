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
func summaryComputesDurationAndStatusCounts() {
    let report = SnapshotReport(
        name: "Summary",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(name: "pass", className: "SuiteTests", status: .passed, duration: 0.2),
                SnapshotTestCase(name: "fail", className: "SuiteTests", status: .failed, duration: 0.3),
                SnapshotTestCase(name: "skip", className: "SuiteTests", status: .skipped, duration: 0.0),
            ])
        ]
    )

    let summary = report.summary
    #expect(summary.total == 3)
    #expect(summary.passed == 1)
    #expect(summary.failed == 1)
    #expect(summary.skipped == 1)
    #expect(summary.duration == 0.5)
}

@Test
func reportAggregatorMergesMetadataWithLastWriterWins() {
    let a = SnapshotReport(name: "A", suites: [], metadata: ["branch": "main", "scheme": "AppA"])
    let b = SnapshotReport(name: "B", suites: [], metadata: ["branch": "release", "target": "UIKit"])

    let merged = SnapshotReportAggregator.merge(reports: [a, b], name: "Merged")

    #expect(merged.metadata["branch"] == "release")
    #expect(merged.metadata["scheme"] == "AppA")
    #expect(merged.metadata["target"] == "UIKit")
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

@Test
func snapshotReportIOSaveAndLoadRoundTrip() throws {
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotReportCoreTests-io-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }

    let url = outputDirectory.appendingPathComponent("roundtrip.json")
    let original = SnapshotReport(
        name: "Roundtrip",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(
                    name: "testSnapshot",
                    className: "SuiteTests",
                    status: .failed,
                    duration: 0.42,
                    failure: SnapshotFailure(message: "mismatch", file: "/tmp/file.swift", line: 12, diff: "diff"),
                    attachments: [SnapshotAttachment(name: "Snapshot", type: .png, path: "/tmp/a.png")],
                    referenceURL: "https://example.com"
                )
            ])
        ],
        metadata: ["branch": "main"]
    )

    try SnapshotReportIO.saveReport(original, to: url)
    let loaded = try SnapshotReportIO.loadReport(from: url)

    #expect(loaded.name == original.name)
    #expect(loaded.suites.count == 1)
    #expect(loaded.suites[0].tests.count == 1)
    #expect(loaded.suites[0].tests[0].failure?.message == "mismatch")
    #expect(loaded.suites[0].tests[0].attachments.first?.type == .png)
    #expect(loaded.metadata["branch"] == "main")
}

@Test(arguments: [
    (SnapshotAttachmentType.png, "image/png"),
    (SnapshotAttachmentType.text, "text/plain"),
    (SnapshotAttachmentType.dump, "text/plain"),
    (SnapshotAttachmentType.binary, "application/octet-stream"),
])
func attachmentTypeMimeTypeMapping(_ type: SnapshotAttachmentType, _ expected: String) {
    #expect(type.mimeType == expected)
}

@Test
func snapshotReportErrorDescriptionsAreStable() {
    #expect(SnapshotReportError.invalidInput("x").description == "Invalid input: x")
    #expect(SnapshotReportError.writeFailed("y").description == "Write failed: y")
}

@Test
func htmlReporterShortensOversizedAttachmentFileNames() throws {
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotReportCoreTests-html-short-name-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = outputDirectory.appendingPathComponent("sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }

    let sourceFile = sourceDirectory.appendingPathComponent("base.png")
    try Data("png".utf8).write(to: sourceFile)
    let longID = String(repeating: "very-long-test-id-", count: 20)

    let report = SnapshotReport(
        name: "LongFile",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(
                    id: longID,
                    name: "testLongName",
                    className: "SuiteTests",
                    status: .passed,
                    duration: 0.01,
                    attachments: [
                        SnapshotAttachment(name: "Snapshot", type: .png, path: sourceFile.path)
                    ]
                )
            ])
        ]
    )

    try SnapshotReportWriters.write(report, format: .html, options: .init(outputDirectory: outputDirectory))

    let attachmentsDir = outputDirectory.appendingPathComponent("html/attachments", isDirectory: true)
    let attachmentFiles = try FileManager.default.contentsOfDirectory(atPath: attachmentsDir.path)
    #expect(attachmentFiles.count == 1)
    #expect(attachmentFiles[0].lengthOfBytes(using: .utf8) <= 240)
    #expect(attachmentFiles[0].hasSuffix(".png"))
}

@Test
func collectorSupportsParallelRecording() async {
    let collector = SnapshotReportCollector(reportName: "Parallel")

    await withTaskGroup(of: Void.self) { group in
        for idx in 0..<100 {
            group.addTask {
                await collector.recordSuccess(
                    suite: idx.isMultiple(of: 2) ? "SuiteA" : "SuiteB",
                    test: "test_\(idx)",
                    className: "ParallelTests",
                    duration: 0.001
                )
            }
        }
    }

    let report = await collector.buildReport()

    #expect(report.summary.total == 100)
    #expect(report.summary.passed == 100)
    #expect(report.summary.failed == 0)
    #expect(report.suites.count == 2)
}

@Test
func htmlReporterOrdersPassedVariantAttachmentsHorizontally() throws {
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotReportCoreTests-html-order-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = outputDirectory.appendingPathComponent("sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }

    let files = [
        "view.dark.png",
        "view.high-contrast-dark.png",
        "view.light.png",
        "view.high-contrast-light.png",
    ]

    for file in files {
        try Data("x".utf8).write(to: sourceDirectory.appendingPathComponent(file))
    }

    let report = SnapshotReport(
        name: "Ordering",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(
                    name: "testVariants",
                    className: "SuiteTests",
                    status: .passed,
                    duration: 0.01,
                    attachments: files.map {
                        SnapshotAttachment(name: "Snapshot", type: .png, path: sourceDirectory.appendingPathComponent($0).path)
                    }
                )
            ])
        ]
    )

    try SnapshotReportWriters.write(report, format: .html, options: .init(outputDirectory: outputDirectory))
    let htmlPath = outputDirectory.appendingPathComponent("html/index.html").path
    let html = try String(contentsOfFile: htmlPath, encoding: .utf8)

    let expected = [
        "high-contrast-light",
        "light",
        "dark",
        "high-contrast-dark",
    ]

    var lastIndex = html.startIndex
    for token in expected {
        guard let range = html.range(of: token, range: lastIndex..<html.endIndex) else {
            Issue.record("Expected token \(token) not found in html output")
            return
        }
        lastIndex = range.upperBound
    }

    #expect(html.contains("attachments passed-variants"))
}

@Test
func htmlReporterRendersFailedDetailsWithSnapshotDiffFailureOrder() throws {
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotReportCoreTests-html-failed-order-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = outputDirectory.appendingPathComponent("sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }

    let files = [
        "failure_1_12345678-1234-1234-1234-123456789ABC.png",
        "difference_2_12345678-1234-1234-1234-123456789ABC.png",
        "reference_0_12345678-1234-1234-1234-123456789ABC.png",
    ]

    for file in files {
        try Data("x".utf8).write(to: sourceDirectory.appendingPathComponent(file))
    }

    let report = SnapshotReport(
        name: "FailedLayout",
        suites: [
            SnapshotSuite(name: "Suite", tests: [
                SnapshotTestCase(
                    name: "testFailed",
                    className: "SuiteTests",
                    status: .failed,
                    duration: 0.01,
                    failure: SnapshotFailure(message: "boom"),
                    attachments: [
                        SnapshotAttachment(name: "Actual Snapshot", type: .png, path: sourceDirectory.appendingPathComponent(files[0]).path),
                        SnapshotAttachment(name: "Diff", type: .png, path: sourceDirectory.appendingPathComponent(files[1]).path),
                        SnapshotAttachment(name: "Snapshot", type: .png, path: sourceDirectory.appendingPathComponent(files[2]).path),
                    ]
                )
            ])
        ]
    )

    try SnapshotReportWriters.write(report, format: .html, options: .init(outputDirectory: outputDirectory))
    let htmlPath = outputDirectory.appendingPathComponent("html/index.html").path
    let html = try String(contentsOfFile: htmlPath, encoding: .utf8)

    #expect(html.contains("failure-details"))
    #expect(html.contains("failed-assert-row"))

    guard
        let snapshotRange = html.range(of: "<div class=\"name\">Snapshot</div>"),
        let diffRange = html.range(of: "<div class=\"name\">Diff</div>", range: snapshotRange.upperBound..<html.endIndex),
        html.range(of: "<div class=\"name\">Failure</div>", range: diffRange.upperBound..<html.endIndex) != nil
    else {
        Issue.record("Expected Snapshot -> Diff -> Failure order in failed details row")
        return
    }
}

@Test
func htmlRendererTemplateCandidatesIncludeResolvedSymlinkPath() throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapshotReportCoreTests-template-candidates-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let cellarBin = temporaryRoot
        .appendingPathComponent("Cellar/snapshot-report-nightly/0.1.0/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: cellarBin, withIntermediateDirectories: true)

    let cellarExecutable = cellarBin.appendingPathComponent("snapshot-report-nightly")
    try Data().write(to: cellarExecutable)

    let linkedBin = temporaryRoot.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: linkedBin, withIntermediateDirectories: true)
    let linkedExecutable = linkedBin.appendingPathComponent("snapshot-report-nightly")
    try FileManager.default.createSymbolicLink(atPath: linkedExecutable.path, withDestinationPath: cellarExecutable.path)

    let candidates = HTMLRenderer.defaultTemplateCandidateURLs(executablePath: linkedExecutable.path).map(\.path)
    let expectedSwiftPMLayout = cellarBin
        .appendingPathComponent("SnapshotReportKit_SnapshotReportCore.bundle/default-report.stencil")
        .path
    let expectedCFBundleLayout = cellarBin
        .appendingPathComponent("SnapshotReportKit_SnapshotReportCore.bundle/Contents/Resources/default-report.stencil")
        .path
    let expectedLibexecSwiftPMLayout = temporaryRoot
        .appendingPathComponent("Cellar/snapshot-report-nightly/0.1.0/libexec/SnapshotReportKit_SnapshotReportCore.bundle/default-report.stencil")
        .path
    let expectedLibexecCFBundleLayout = temporaryRoot
        .appendingPathComponent("Cellar/snapshot-report-nightly/0.1.0/libexec/SnapshotReportKit_SnapshotReportCore.bundle/Contents/Resources/default-report.stencil")
        .path

    #expect(candidates.contains(expectedSwiftPMLayout))
    #expect(candidates.contains(expectedCFBundleLayout))
    #expect(candidates.contains(expectedLibexecSwiftPMLayout))
    #expect(candidates.contains(expectedLibexecCFBundleLayout))
}

@Test
func htmlRendererTemplateCandidatesIncludeSourceFallback() {
    let candidates = HTMLRenderer.defaultTemplateCandidateURLs(executablePath: "/tmp/snapshot-report").map(\.path)
    #expect(candidates.contains { $0.hasSuffix("/Sources/SnapshotReportCore/Resources/default-report.stencil") })
}

@Test
func htmlRendererTemplateCandidatesIncludeBrewShareFallbacks() {
    let executablePath = "/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/bin/snapshot-report-nightly"
    let candidates = HTMLRenderer.defaultTemplateCandidateURLs(executablePath: executablePath).map(\.path)

    #expect(candidates.contains("/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/bin/SnapshotReportKit_SnapshotReportCore.bundle/default-report.stencil"))
    #expect(candidates.contains("/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/libexec/SnapshotReportKit_SnapshotReportCore.bundle/default-report.stencil"))
    #expect(candidates.contains("/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/share/snapshot-report/SnapshotReportKit_SnapshotReportCore.bundle/default-report.stencil"))
}

@Test
func htmlRendererTemplateCandidatesIncludeEnvironmentOverrides() {
    let candidates = HTMLRenderer.environmentTemplateCandidateURLs(
        environment: [
            "SNAPSHOT_REPORT_HTML_TEMPLATE": "/tmp/custom-template.stencil",
            "SNAPSHOT_REPORT_RESOURCE_BUNDLE": "/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/bin/SnapshotReportKit_SnapshotReportCore.bundle",
            "SNAPSHOT_REPORT_INSTALL_ROOT": "/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/bin",
        ]
    ).map(\.path)

    #expect(candidates.contains("/tmp/custom-template.stencil"))
    #expect(candidates.contains("/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/bin/SnapshotReportKit_SnapshotReportCore.bundle/default-report.stencil"))
    #expect(candidates.contains("/opt/homebrew/Cellar/snapshot-report-nightly/2026.02.20.6/bin/SnapshotReportKit_SnapshotReportCore.bundle/Contents/Resources/default-report.stencil"))
}
