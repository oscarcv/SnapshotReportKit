import Foundation

/// Reporter contract implemented by all output backends (JSON, JUnit, HTML).
public protocol SnapshotReporter: Sendable {
    /// Output format produced by the reporter.
    var format: OutputFormat { get }
    /// Writes the provided report to disk using the supplied options.
    /// - Parameters:
    ///   - report: Report model to persist.
    ///   - options: Output options.
    func write(report: SnapshotReport, options: ReportWriteOptions) throws
}
