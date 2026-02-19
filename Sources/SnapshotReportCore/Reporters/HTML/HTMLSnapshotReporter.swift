import Foundation
import Stencil

public struct HTMLSnapshotReporter: SnapshotReporter {
    public let format: OutputFormat = .html

    public init() {}

    public func write(report: SnapshotReport, options: ReportWriteOptions) throws {
        let outputDir = options.outputDirectory.appendingPathComponent("html", isDirectory: true)
        try HTMLRenderer().render(report: report, outputDirectory: outputDir, customTemplatePath: options.htmlTemplatePath)
    }
}

struct HTMLRenderer {
    private let fileManager = FileManager.default

    func render(report: SnapshotReport, outputDirectory: URL, customTemplatePath: String?) throws {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let attachmentDir = outputDirectory.appendingPathComponent("attachments", isDirectory: true)
        try fileManager.createDirectory(at: attachmentDir, withIntermediateDirectories: true)

        let reportWithCopiedAttachments = try copyAttachments(for: report, into: attachmentDir)
        let html = try renderTemplate(
            report: reportWithCopiedAttachments,
            outputDirectory: outputDirectory,
            customTemplatePath: customTemplatePath
        )
        try html.write(to: outputDirectory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    private func copyAttachments(for report: SnapshotReport, into attachmentDir: URL) throws -> SnapshotReport {
        var suites = report.suites

        for suiteIndex in suites.indices {
            for caseIndex in suites[suiteIndex].tests.indices {
                var testCase = suites[suiteIndex].tests[caseIndex]
                testCase.attachments = try testCase.attachments.map { attachment in
                    let source = URL(fileURLWithPath: attachment.path)
                    if !fileManager.fileExists(atPath: source.path) {
                        return attachment
                    }

                    let safeName = sanitize("\(testCase.id)-\(source.lastPathComponent)")
                    let destination = attachmentDir.appendingPathComponent(safeName)
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.copyItem(at: source, to: destination)

                    return SnapshotAttachment(name: attachment.name, type: attachment.type, path: "attachments/\(safeName)")
                }
                suites[suiteIndex].tests[caseIndex] = testCase
            }
        }

        return SnapshotReport(name: report.name, generatedAt: report.generatedAt, suites: suites, metadata: report.metadata)
    }

    private func renderTemplate(report: SnapshotReport, outputDirectory: URL, customTemplatePath: String?) throws -> String {
        let template: String
        if let customTemplatePath {
            template = try String(contentsOfFile: customTemplatePath, encoding: .utf8)
        } else {
            guard let resourceURL = Bundle.module.url(forResource: "default-report", withExtension: "stencil") else {
                throw SnapshotReportError.writeFailed("Missing bundled template")
            }
            template = try String(contentsOf: resourceURL, encoding: .utf8)
        }

        let environment = Environment(trimBehaviour: .smart)
        return try environment.renderTemplate(string: template, context: makeContext(report: report, outputDirectory: outputDirectory))
    }

    private func makeContext(report: SnapshotReport, outputDirectory: URL) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "report": [
                "name": report.name,
                "generatedAt": formatter.string(from: report.generatedAt),
                "summary": [
                    "total": report.summary.total,
                    "passed": report.summary.passed,
                    "failed": report.summary.failed,
                    "skipped": report.summary.skipped,
                    "duration": String(format: "%.3f", report.summary.duration)
                ]
            ],
            "suites": report.suites.map { suite in
                [
                    "name": suite.name,
                    "tests": suite.tests.map { test in
                        let orderedAttachments = sortAttachmentsForVariantDisplay(test.attachments)
                        return [
                            "id": test.id,
                            "name": test.name,
                            "className": test.className,
                            "status": test.status.rawValue,
                            "duration": String(format: "%.3f", test.duration),
                            "failure": [
                                "message": test.failure?.message ?? "",
                                "file": test.failure?.file ?? "",
                                "line": test.failure?.line.map(String.init) ?? "",
                                "diff": test.failure?.diff ?? ""
                            ],
                            "attachments": orderedAttachments.map { attachment in
                                let fullPath = outputDirectory.appendingPathComponent(attachment.path).path
                                let textContent: String
                                if attachment.type == .text || attachment.type == .dump {
                                    textContent = (try? String(contentsOfFile: fullPath, encoding: .utf8)) ?? ""
                                } else {
                                    textContent = ""
                                }

                                return [
                                    "name": attachment.name,
                                    "type": attachment.type.rawValue,
                                    "path": attachment.path,
                                    "content": textContent,
                                    "variantOrder": variantOrder(for: attachment.path)
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "-", options: .regularExpression)
    }

    private func sortAttachmentsForVariantDisplay(_ attachments: [SnapshotAttachment]) -> [SnapshotAttachment] {
        attachments.sorted { lhs, rhs in
            let leftOrder = variantOrder(for: lhs.path)
            let rightOrder = variantOrder(for: rhs.path)

            if leftOrder == rightOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return leftOrder < rightOrder
        }
    }

    private func variantOrder(for path: String) -> Int {
        let value = path.lowercased()

        if value.contains("high-contrast-light") { return 0 }
        if value.contains("light") && value.contains("high-contrast") == false { return 1 }
        if value.contains("dark") && value.contains("high-contrast") == false { return 2 }
        if value.contains("high-contrast-dark") { return 3 }

        return 999
    }
}
