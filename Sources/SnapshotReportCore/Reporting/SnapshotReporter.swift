import Foundation

public protocol SnapshotReporter: Sendable {
    var format: OutputFormat { get }
    func write(report: SnapshotReport, options: ReportWriteOptions) throws
}
