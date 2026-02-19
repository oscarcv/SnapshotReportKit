import Foundation

public enum OutputFormat: String, CaseIterable, Sendable {
    case json
    case junit
    case html
}

public struct ReportWriteOptions: Sendable {
    public var outputDirectory: URL
    public var htmlTemplatePath: String?

    public init(outputDirectory: URL, htmlTemplatePath: String? = nil) {
        self.outputDirectory = outputDirectory
        self.htmlTemplatePath = htmlTemplatePath
    }
}

public enum SnapshotReportWriters {
    public static func write(_ report: SnapshotReport, format: OutputFormat, options: ReportWriteOptions) throws {
        let reporter = reporter(for: format)
        try reporter.write(report: report, options: options)
    }

    static func reporter(for format: OutputFormat) -> any SnapshotReporter {
        switch format {
        case .json:
            return JSONSnapshotReporter()
        case .junit:
            return JUnitSnapshotReporter()
        case .html:
            return HTMLSnapshotReporter()
        }
    }
}
