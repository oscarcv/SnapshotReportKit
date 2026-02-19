import Foundation

public actor SnapshotReportCollector {
    private var suites: [String: [SnapshotTestCase]] = [:]
    private let reportName: String

    public init(reportName: String = "Snapshot Tests") {
        self.reportName = reportName
    }

    public func recordSuccess(
        suite: String,
        test: String,
        className: String,
        duration: TimeInterval,
        attachments: [SnapshotAttachment] = [],
        referenceURL: String? = nil
    ) {
        append(
            suite: suite,
            testCase: SnapshotTestCase(
                name: test,
                className: className,
                status: .passed,
                duration: duration,
                attachments: attachments,
                referenceURL: referenceURL
            )
        )
    }

    public func recordFailure(
        suite: String,
        test: String,
        className: String,
        duration: TimeInterval,
        message: String,
        file: String? = nil,
        line: Int? = nil,
        diff: String? = nil,
        attachments: [SnapshotAttachment] = [],
        referenceURL: String? = nil
    ) {
        append(
            suite: suite,
            testCase: SnapshotTestCase(
                name: test,
                className: className,
                status: .failed,
                duration: duration,
                failure: SnapshotFailure(message: message, file: file, line: line, diff: diff),
                attachments: attachments,
                referenceURL: referenceURL
            )
        )
    }

    public func recordSkipped(
        suite: String,
        test: String,
        className: String,
        duration: TimeInterval = 0
    ) {
        append(
            suite: suite,
            testCase: SnapshotTestCase(
                name: test,
                className: className,
                status: .skipped,
                duration: duration
            )
        )
    }

    public func buildReport(metadata: [String: String] = [:]) -> SnapshotReport {
        let suiteModels = suites
            .map { SnapshotSuite(name: $0.key, tests: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return SnapshotReport(name: reportName, generatedAt: Date(), suites: suiteModels, metadata: metadata)
    }

    public func writeJSON(to url: URL, metadata: [String: String] = [:]) throws {
        try SnapshotReportIO.saveReport(buildReport(metadata: metadata), to: url)
    }

    private func append(suite: String, testCase: SnapshotTestCase) {
        if suites[suite] != nil {
            suites[suite]?.append(testCase)
        } else {
            suites[suite] = [testCase]
        }
    }
}
