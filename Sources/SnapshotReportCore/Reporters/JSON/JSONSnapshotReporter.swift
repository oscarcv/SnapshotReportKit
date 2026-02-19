import Foundation

public struct JSONSnapshotReporter: SnapshotReporter {
    public let format: OutputFormat = .json

    public init() {}

    public func write(report: SnapshotReport, options: ReportWriteOptions) throws {
        let fileURL = options.outputDirectory.appendingPathComponent("report.json")
        try SnapshotReportIO.saveReport(report, to: fileURL)
    }
}
