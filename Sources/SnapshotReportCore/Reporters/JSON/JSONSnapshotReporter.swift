import Foundation

/// Reporter that writes the merged model as JSON.
public struct JSONSnapshotReporter: SnapshotReporter {
    public let format: OutputFormat = .json

    /// Creates a JSON reporter.
    public init() {}

    /// Writes `report.json` into `options.outputDirectory`.
    public func write(report: SnapshotReport, options: ReportWriteOptions) throws {
        let fileURL = options.outputDirectory.appendingPathComponent("report.json")
        try SnapshotReportIO.saveReport(report, to: fileURL)
    }
}
