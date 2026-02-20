import Foundation

/// Output formats supported by the CLI/reporting pipeline.
public enum OutputFormat: String, CaseIterable, Sendable {
    /// JSON report output (`report.json`).
    case json
    /// JUnit XML report output (`report.junit.xml`).
    case junit
    /// Static HTML report output (`html/index.html`).
    case html
}

/// Options used by reporter implementations when writing artifacts.
public struct ReportWriteOptions: Sendable {
    /// Base output directory.
    public var outputDirectory: URL
    /// Optional custom HTML stencil template path.
    public var htmlTemplatePath: String?

    /// Creates write options.
    /// - Parameters:
    ///   - outputDirectory: Base output directory.
    ///   - htmlTemplatePath: Optional custom HTML template path.
    public init(outputDirectory: URL, htmlTemplatePath: String? = nil) {
        self.outputDirectory = outputDirectory
        self.htmlTemplatePath = htmlTemplatePath
    }
}

/// Dispatcher that resolves and runs built-in reporters.
public enum SnapshotReportWriters {
    /// Writes the report in a specific output format.
    /// - Parameters:
    ///   - report: Report to write.
    ///   - format: Output format.
    ///   - options: Reporter options.
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
