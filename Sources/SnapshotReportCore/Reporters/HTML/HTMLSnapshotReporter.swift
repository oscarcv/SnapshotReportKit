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
        let summaryDict: [String: Any] = [
            "total": report.summary.total,
            "passed": report.summary.passed,
            "failed": report.summary.failed,
            "skipped": report.summary.skipped,
            "duration": String(format: "%.3f", report.summary.duration)
        ]
        let reportDict: [String: Any] = [
            "name": report.name,
            "generatedAt": formatter.string(from: report.generatedAt),
            "summary": summaryDict
        ]
        let suitesArray: [[String: Any]] = report.suites.map { suite in
            let testsArray: [[String: Any]] = suite.tests.map { test in
                makeTestContext(test: test, outputDirectory: outputDirectory)
            }
            return ["name": suite.name, "tests": testsArray]
        }
        return ["report": reportDict, "suites": suitesArray]
    }

    private func makeTestContext(test: SnapshotTestCase, outputDirectory: URL) -> [String: Any] {
        let orderedAttachments = sortAttachmentsForVariantDisplay(test.attachments)
        let attachmentsArray: [[String: Any]] = orderedAttachments.map { attachment in
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
        let failedGroups = makeFailedAttachmentGroups(for: test, outputDirectory: outputDirectory)
        let passedGroups = makePassedAttachmentGroups(for: test, outputDirectory: outputDirectory)
        let failureDict: [String: Any] = [
            "message": test.failure?.message ?? "",
            "file": test.failure?.file ?? "",
            "line": test.failure?.line.map(String.init) ?? "",
            "diff": test.failure?.diff ?? ""
        ]
        return [
            "id": test.id,
            "name": test.name,
            "className": test.className,
            "status": test.status.rawValue,
            "duration": String(format: "%.3f", test.duration),
            "failure": failureDict,
            "referenceURL": test.referenceURL ?? "",
            "attachments": attachmentsArray,
            "failedGroups": failedGroups,
            "passedGroups": passedGroups
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

    private func makeFailedAttachmentGroups(for test: SnapshotTestCase, outputDirectory: URL) -> [[String: Any]] {
        guard test.status == .failed else { return [] }

        struct Group {
            var snapshot: SnapshotAttachment?
            var diff: SnapshotAttachment?
            var failure: SnapshotAttachment?
        }

        var groups: [String: Group] = [:]
        var orderedKeys: [String] = []
        var ungroupedIndex = 0

        for attachment in test.attachments {
            guard let kind = failedAttachmentKind(for: attachment) else { continue }
            let key = failedAttachmentGroupKey(for: attachment) ?? "ungrouped-\(ungroupedIndex)"
            if failedAttachmentGroupKey(for: attachment) == nil {
                ungroupedIndex += 1
            }

            if groups[key] == nil {
                groups[key] = Group()
                orderedKeys.append(key)
            }

            switch kind {
            case "snapshot":
                groups[key]?.snapshot = attachment
            case "diff":
                groups[key]?.diff = attachment
            case "failure":
                groups[key]?.failure = attachment
            default:
                break
            }
        }

        return orderedKeys.compactMap { key in
            guard let group = groups[key] else { return nil }
            if group.snapshot == nil && group.diff == nil && group.failure == nil {
                return nil
            }
            let groupName = failedGroupName(
                key: key,
                snapshot: group.snapshot,
                failure: group.failure
            )
            return [
                "groupName": groupName,
                "snapshot": attachmentContext(group.snapshot, label: "Snapshot", outputDirectory: outputDirectory),
                "diff": attachmentContext(group.diff, label: "Diff", outputDirectory: outputDirectory),
                "failure": attachmentContext(group.failure, label: "Failure", outputDirectory: outputDirectory),
            ]
        }
    }

    private func makePassedAttachmentGroups(for test: SnapshotTestCase, outputDirectory: URL) -> [[String: Any]] {
        guard test.status == .passed else { return [] }
        guard !test.attachments.isEmpty else { return [] }

        var grouped: [String: [SnapshotAttachment]] = [:]
        var order: [String] = []

        for attachment in sortAttachmentsForVariantDisplay(test.attachments) {
            let key = passedGroupName(for: attachment)
            if grouped[key] == nil {
                grouped[key] = []
                order.append(key)
            }
            grouped[key, default: []].append(attachment)
        }

        return order.map { key in
            let items: [[String: Any]] = grouped[key, default: []].map { attachment in
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
            return [
                "groupName": key,
                "attachments": items
            ]
        }
    }

    private func failedAttachmentKind(for attachment: SnapshotAttachment) -> String? {
        let value = attachment.name.lowercased()
        if value == "snapshot" || value.contains("reference") { return "snapshot" }
        if value == "diff" || value == "odiff" || value.contains("difference") { return "diff" }
        if value == "actual snapshot" || value.contains("failure") || value.contains("actual") || value.contains("current") {
            return "failure"
        }
        return nil
    }

    private func failedAttachmentGroupKey(for attachment: SnapshotAttachment) -> String? {
        let filename = URL(fileURLWithPath: attachment.path).lastPathComponent
        let patterns = [
            #"(?:reference|failure|difference)_\d+_([A-F0-9-]+)\.(?:png|jpg|jpeg)$"#,
            #"(?:reference|failure|difference)-([A-F0-9-]+)\.(?:png|jpg|jpeg)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(location: 0, length: filename.utf16.count)
            guard let match = regex.firstMatch(in: filename, options: [], range: range), match.numberOfRanges > 1 else { continue }
            if let captureRange = Range(match.range(at: 1), in: filename) {
                return String(filename[captureRange])
            }
        }

        return nil
    }

    private func attachmentContext(_ attachment: SnapshotAttachment?, label: String, outputDirectory: URL) -> [String: Any] {
        guard let attachment else {
            return [
                "exists": false,
                "name": label,
                "type": "",
                "path": "",
                "content": ""
            ]
        }

        let fullPath = outputDirectory.appendingPathComponent(attachment.path).path
        let textContent: String
        if attachment.type == .text || attachment.type == .dump {
            textContent = (try? String(contentsOfFile: fullPath, encoding: .utf8)) ?? ""
        } else {
            textContent = ""
        }

        return [
            "exists": true,
            "name": label,
            "type": attachment.type.rawValue,
            "path": attachment.path,
            "content": textContent
        ]
    }

    private func passedGroupName(for attachment: SnapshotAttachment) -> String {
        let candidate = attachment.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            "-high-contrast-light",
            "-high-contrast-dark",
            "-light",
            "-dark"
        ]

        for suffix in suffixes {
            if candidate.lowercased().hasSuffix(suffix) {
                return String(candidate.dropLast(suffix.count))
            }
        }

        return candidate
    }

    private func failedGroupName(key: String, snapshot: SnapshotAttachment?, failure: SnapshotAttachment?) -> String {
        if let snapshot {
            let raw = URL(fileURLWithPath: snapshot.path).deletingPathExtension().lastPathComponent
            if let name = extractNamedSegment(from: raw) {
                return name
            }
        }
        if let failure {
            let raw = URL(fileURLWithPath: failure.path).deletingPathExtension().lastPathComponent
            if let name = extractNamedSegment(from: raw) {
                return name
            }
        }
        if key.hasPrefix("ungrouped-"),
           let index = Int(key.replacingOccurrences(of: "ungrouped-", with: "")) {
            return "assert-\(index + 1)"
        }
        return key
    }

    private func extractNamedSegment(from filename: String) -> String? {
        if let range = filename.range(of: #"^[^.]+\.(.+)$"#, options: .regularExpression) {
            var value = String(filename[range]).replacingOccurrences(of: #"^[^.]+\."#, with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: #"\.(png|jpg|jpeg)$"#, with: "", options: .regularExpression)
            let suffixes = ["-high-contrast-light", "-high-contrast-dark", "-light", "-dark"]
            for suffix in suffixes where value.lowercased().hasSuffix(suffix) {
                return String(value.dropLast(suffix.count))
            }
            return value
        }
        return nil
    }
}
