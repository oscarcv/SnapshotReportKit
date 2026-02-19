import Foundation

public struct JUnitSnapshotReporter: SnapshotReporter {
    public let format: OutputFormat = .junit

    public init() {}

    public func write(report: SnapshotReport, options: ReportWriteOptions) throws {
        let fileURL = options.outputDirectory.appendingPathComponent("report.junit.xml")
        let content = JUnitXMLRenderer().render(report: report)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

struct JUnitXMLRenderer {
    func render(report: SnapshotReport) -> String {
        let summary = report.summary
        let suitesXML = report.suites.map(renderSuite).joined(separator: "\n")
        let timestamp = ISO8601DateFormatter().string(from: report.generatedAt)

        return """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <testsuites name=\"\(escape(report.name))\" tests=\"\(summary.total)\" failures=\"\(summary.failed)\" skipped=\"\(summary.skipped)\" time=\"\(summary.duration)\" timestamp=\"\(timestamp)\">\n\(suitesXML)
        </testsuites>
        """
    }

    private func renderSuite(_ suite: SnapshotSuite) -> String {
        let failures = suite.tests.filter { $0.status == .failed }.count
        let skipped = suite.tests.filter { $0.status == .skipped }.count
        let totalTime = suite.tests.reduce(0) { $0 + $1.duration }
        let testCases = suite.tests.map(renderCase).joined(separator: "\n")
        return """
          <testsuite name=\"\(escape(suite.name))\" tests=\"\(suite.tests.count)\" failures=\"\(failures)\" skipped=\"\(skipped)\" time=\"\(totalTime)\">\n\(testCases)
          </testsuite>
        """
    }

    private func renderCase(_ test: SnapshotTestCase) -> String {
        var lines: [String] = []
        lines.append("    <testcase classname=\"\(escape(test.className))\" name=\"\(escape(test.name))\" time=\"\(test.duration)\">")

        if test.status == .skipped {
            lines.append("      <skipped/>")
        }

        if test.status == .failed {
            let failureMessage = escape(test.failure?.message ?? "Snapshot assertion failed")
            let failureBody = escape(test.failure?.diff ?? "")
            lines.append("      <failure message=\"\(failureMessage)\">\(failureBody)</failure>")
        }

        if !test.attachments.isEmpty {
            lines.append("      <attachments>")
            for attachment in test.attachments {
                lines.append("        <attachment name=\"\(escape(attachment.name))\" path=\"\(escape(attachment.path))\" type=\"\(attachment.type.mimeType)\" />")
            }
            lines.append("      </attachments>")
            let output = test.attachments.map { "\($0.name): \($0.path)" }.joined(separator: " | ")
            lines.append("      <system-out>\(escape(output))</system-out>")
        }

        lines.append("    </testcase>")
        return lines.joined(separator: "\n")
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
