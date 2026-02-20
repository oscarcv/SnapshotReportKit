import Foundation

/// Concurrency-safe collector used to build a `SnapshotReport` incrementally.
public actor SnapshotReportCollector {
    private var suites: [String: [SnapshotTestCase]] = [:]
    private let reportName: String

    /// Creates a collector.
    /// - Parameter reportName: Name used for the final report.
    public init(reportName: String = "Snapshot Tests") {
        self.reportName = reportName
    }

    /// Records a passed snapshot test case.
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

    /// Records a failed snapshot test case.
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

    /// Records a skipped snapshot test case.
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

    /// Builds an immutable report from currently recorded results.
    /// - Parameter metadata: Optional report-level metadata.
    /// - Returns: Aggregated report.
    public func buildReport(metadata: [String: String] = [:]) -> SnapshotReport {
        let suiteModels = suites
            .map { SnapshotSuite(name: $0.key, tests: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return SnapshotReport(name: reportName, generatedAt: Date(), suites: suiteModels, metadata: metadata)
    }

    /// Writes the current report as JSON to disk.
    /// - Parameters:
    ///   - url: Destination path.
    ///   - metadata: Optional report-level metadata.
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
