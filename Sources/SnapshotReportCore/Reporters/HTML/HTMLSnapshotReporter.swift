import Foundation
import Stencil

/// Reporter that produces a static HTML report with copied attachments.
public struct HTMLSnapshotReporter: SnapshotReporter {
    public let format: OutputFormat = .html

    /// Creates an HTML reporter.
    public init() {}

    /// Writes HTML report artifacts into `options.outputDirectory/html`.
    public func write(report: SnapshotReport, options: ReportWriteOptions) throws {
        let outputDir = options.outputDirectory.appendingPathComponent("html", isDirectory: true)
        try HTMLRenderer().render(report: report, outputDirectory: outputDir, customTemplatePath: options.htmlTemplatePath)
    }
}

struct HTMLRenderer {
    private let fileManager = FileManager.default
    private let maxFilenameBytes = 240

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
        var jobs: [AttachmentCopyJob] = []

        for suiteIndex in suites.indices {
            for caseIndex in suites[suiteIndex].tests.indices {
                let testCase = suites[suiteIndex].tests[caseIndex]
                for attachmentIndex in testCase.attachments.indices {
                    jobs.append(.init(
                        suiteIndex: suiteIndex,
                        testIndex: caseIndex,
                        attachmentIndex: attachmentIndex,
                        testID: testCase.id,
                        attachment: testCase.attachments[attachmentIndex]
                    ))
                }
            }
        }

        let workerCount = max(1, min(ProcessInfo.processInfo.activeProcessorCount, jobs.count))
        let queue = DispatchQueue(label: "snapshot-report.html.copy.queue", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: workerCount)
        let group = DispatchGroup()
        let state = AttachmentCopyState()
        let maxFilenameBytes = self.maxFilenameBytes

        for job in jobs {
            group.enter()
            semaphore.wait()
            queue.async {
                defer {
                    semaphore.signal()
                    group.leave()
                }
                do {
                    let copied = try HTMLRenderer.copyAttachment(
                        job: job,
                        into: attachmentDir,
                        maxFilenameBytes: maxFilenameBytes
                    )
                    state.set(attachment: copied.attachment, warning: copied.warning, for: job.key)
                } catch {
                    state.setFirstErrorIfNeeded(error)
                }
            }
        }

        group.wait()
        if let firstError = state.firstError() {
            throw firstError
        }

        for warning in state.warnings().sorted() {
            fputs("[snapshot-report] warning: \(warning)\n", stderr)
        }
        for job in jobs {
            guard let copied = state.attachment(for: job.key) else { continue }
            suites[job.suiteIndex].tests[job.testIndex].attachments[job.attachmentIndex] = copied
        }

        return SnapshotReport(name: report.name, generatedAt: report.generatedAt, suites: suites, metadata: report.metadata)
    }

    private func renderTemplate(report: SnapshotReport, outputDirectory: URL, customTemplatePath: String?) throws -> String {
        let template = try loadTemplate(customTemplatePath: customTemplatePath)

        let environment = Environment(trimBehaviour: .smart)
        return try environment.renderTemplate(string: template, context: makeContext(report: report, outputDirectory: outputDirectory))
    }

    private func loadTemplate(customTemplatePath: String?) throws -> String {
        if let customTemplatePath {
            return try String(contentsOfFile: customTemplatePath, encoding: .utf8)
        }

        for candidate in Self.environmentTemplateCandidateURLs() + Self.defaultTemplateCandidateURLs() {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            return try String(contentsOf: candidate, encoding: .utf8)
        }

        let searchedPaths = (Self.environmentTemplateCandidateURLs() + Self.defaultTemplateCandidateURLs())
            .map(\.path)
            .joined(separator: "\n- ")
        throw SnapshotReportError.writeFailed(
            """
            Missing bundled template (default-report.stencil).
            Searched:
            - \(searchedPaths)
            Provide --html-template <path> or reinstall snapshot-report.
            """
        )
    }

    static func defaultTemplateCandidateURLs(
        executablePath: String = CommandLine.arguments.first ?? ""
    ) -> [URL] {
        let bundleName = "SnapshotReportKit_SnapshotReportCore.bundle"
        let templateRelativePaths = [
            "default-report.stencil",
            "Contents/Resources/default-report.stencil",
        ]
        let templateBasenames = ["default-report.stencil"]
        let bundleBaseRelativeDirectories = [
            "",
            "libexec",
            "share",
            "share/snapshot-report",
            "Resources",
        ]
        var candidateDirectories: [URL] = []

        if executablePath.isEmpty == false {
            let providedExecURL = URL(fileURLWithPath: executablePath)
            candidateDirectories.append(providedExecURL.deletingLastPathComponent())

            let resolvedExecURL = providedExecURL.resolvingSymlinksInPath()
            candidateDirectories.append(resolvedExecURL.deletingLastPathComponent())
        }

        var seenDirectoryPaths = Set<String>()
        var uniqueDirectories: [URL] = []
        for directory in candidateDirectories {
            let standardized = directory.standardizedFileURL.path
            if seenDirectoryPaths.insert(standardized).inserted {
                uniqueDirectories.append(directory)
            }
        }

        var searchRoots: [URL] = []
        for directory in uniqueDirectories {
            var current = directory
            for _ in 0..<5 {
                searchRoots.append(current)
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }

        var seenRootPaths = Set<String>()
        var uniqueRoots: [URL] = []
        for root in searchRoots {
            let standardized = root.standardizedFileURL.path
            if seenRootPaths.insert(standardized).inserted {
                uniqueRoots.append(root)
            }
        }

        var candidates: [URL] = []
        for root in uniqueRoots {
            for baseRelativeDirectory in bundleBaseRelativeDirectories {
                let base = baseRelativeDirectory.isEmpty
                    ? root
                    : root.appendingPathComponent(baseRelativeDirectory, isDirectory: true)

                for templateRelativePath in templateRelativePaths {
                    let bundledTemplate = base
                        .appendingPathComponent(bundleName, isDirectory: true)
                        .appendingPathComponent(templateRelativePath)
                    candidates.append(bundledTemplate)
                }

                for templateBasename in templateBasenames {
                    candidates.append(base.appendingPathComponent(templateBasename))
                }
            }
        }

        let sourceTemplate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/default-report.stencil")
        candidates.append(sourceTemplate)

        var seenCandidatePaths = Set<String>()
        var uniqueCandidates: [URL] = []
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL.path
            if seenCandidatePaths.insert(standardized).inserted {
                uniqueCandidates.append(candidate)
            }
        }
        return uniqueCandidates
    }

    static func environmentTemplateCandidateURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        let templateRelativePaths = [
            "default-report.stencil",
            "Contents/Resources/default-report.stencil",
        ]
        let bundleName = "SnapshotReportKit_SnapshotReportCore.bundle"
        var candidates: [URL] = []

        if let templatePath = environment["SNAPSHOT_REPORT_HTML_TEMPLATE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           templatePath.isEmpty == false {
            candidates.append(URL(fileURLWithPath: templatePath))
        }
        if let bundlePath = environment["SNAPSHOT_REPORT_RESOURCE_BUNDLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           bundlePath.isEmpty == false {
            let bundleURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
            for templateRelativePath in templateRelativePaths {
                candidates.append(bundleURL.appendingPathComponent(templateRelativePath))
            }
        }
        if let installRoot = environment["SNAPSHOT_REPORT_INSTALL_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           installRoot.isEmpty == false {
            let rootURL = URL(fileURLWithPath: installRoot, isDirectory: true)
            for templateRelativePath in templateRelativePaths {
                candidates.append(
                    rootURL
                        .appendingPathComponent(bundleName, isDirectory: true)
                        .appendingPathComponent(templateRelativePath)
                )
            }
        }

        return candidates
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
            let metadata = attachmentFileMetadata(fullPath: fullPath)
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
                "variantOrder": variantOrder(for: attachment.path),
                "exists": metadata.exists,
                "isEmpty": metadata.isEmpty,
                "sizeBytes": metadata.sizeBytes
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

    private static func copyAttachment(
        job: AttachmentCopyJob,
        into attachmentDir: URL,
        maxFilenameBytes: Int
    ) throws -> (attachment: SnapshotAttachment, warning: String?) {
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: job.attachment.path)
        guard fileManager.fileExists(atPath: source.path) else {
            return (job.attachment, nil)
        }

        let originalFilename = sanitize("\(job.testID)-\(source.lastPathComponent)")
        let shortened = shortenFilenameIfNeeded(
            originalFilename,
            maxBytes: maxFilenameBytes,
            hashSeed: "\(job.testID)|\(source.path)"
        )
        let destination = attachmentDir.appendingPathComponent(shortened.filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)

        return (
            SnapshotAttachment(name: job.attachment.name, type: job.attachment.type, path: "attachments/\(shortened.filename)"),
            shortened.warning
        )
    }

    private static func shortenFilenameIfNeeded(_ filename: String, maxBytes: Int, hashSeed: String) -> (filename: String, warning: String?) {
        guard filename.lengthOfBytes(using: .utf8) > maxBytes else {
            return (filename, nil)
        }

        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let hash = shortHash(hashSeed)
        let suffix = ext.isEmpty ? "-\(hash)" : "-\(hash).\(ext)"
        let availableBytes = max(1, maxBytes - suffix.lengthOfBytes(using: .utf8))
        let shortenedBase = String(decoding: base.utf8.prefix(availableBytes), as: UTF8.self)
        let shortened = shortenedBase + suffix
        let warning = "Attachment filename exceeded \(maxBytes) bytes and was shortened: \(filename) -> \(shortened)"
        return (shortened, warning)
    }

    private static func shortHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func sanitize(_ value: String) -> String {
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
                let metadata = attachmentFileMetadata(fullPath: fullPath)
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
                    "variantOrder": variantOrder(for: attachment.path),
                    "exists": metadata.exists,
                    "isEmpty": metadata.isEmpty,
                    "sizeBytes": metadata.sizeBytes
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
        let rawName = attachment.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardizedPrefixes = ["Snapshot-", "Diff-", "Failure-", "Actual Snapshot-"]
        for prefix in standardizedPrefixes where rawName.hasPrefix(prefix) {
            return String(rawName.dropFirst(prefix.count))
        }

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
                "isEmpty": true,
                "name": label,
                "type": "",
                "path": "",
                "content": "",
                "sizeBytes": 0
            ]
        }

        let fullPath = outputDirectory.appendingPathComponent(attachment.path).path
        let metadata = attachmentFileMetadata(fullPath: fullPath)
        let textContent: String
        if attachment.type == .text || attachment.type == .dump {
            textContent = (try? String(contentsOfFile: fullPath, encoding: .utf8)) ?? ""
        } else {
            textContent = ""
        }

        return [
            "exists": metadata.exists,
            "isEmpty": metadata.isEmpty,
            "name": label,
            "type": attachment.type.rawValue,
            "path": attachment.path,
            "content": textContent,
            "sizeBytes": metadata.sizeBytes
        ]
    }

    private func attachmentFileMetadata(fullPath: String) -> (exists: Bool, isEmpty: Bool, sizeBytes: Int64) {
        guard fileManager.fileExists(atPath: fullPath) else {
            return (exists: false, isEmpty: true, sizeBytes: 0)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: fullPath)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return (exists: true, isEmpty: size == 0, sizeBytes: size)
    }

    private func passedGroupName(for attachment: SnapshotAttachment) -> String {
        var candidate = attachment.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("Snapshot-") {
            candidate = String(candidate.dropFirst("Snapshot-".count))
        }
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

private struct AttachmentCopyJob: Sendable {
    let suiteIndex: Int
    let testIndex: Int
    let attachmentIndex: Int
    let testID: String
    let attachment: SnapshotAttachment

    var key: AttachmentCopyKey {
        AttachmentCopyKey(suiteIndex: suiteIndex, testIndex: testIndex, attachmentIndex: attachmentIndex)
    }
}

private struct AttachmentCopyKey: Hashable, Sendable {
    let suiteIndex: Int
    let testIndex: Int
    let attachmentIndex: Int
}

private final class AttachmentCopyState: @unchecked Sendable {
    private let lock = NSLock()
    private var attachmentsByKey: [AttachmentCopyKey: SnapshotAttachment] = [:]
    private var warningMessages: Set<String> = []
    private var storedError: Error?

    func set(attachment: SnapshotAttachment, warning: String?, for key: AttachmentCopyKey) {
        lock.lock()
        attachmentsByKey[key] = attachment
        if let warning {
            warningMessages.insert(warning)
        }
        lock.unlock()
    }

    func attachment(for key: AttachmentCopyKey) -> SnapshotAttachment? {
        lock.lock()
        defer { lock.unlock() }
        return attachmentsByKey[key]
    }

    func warnings() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(warningMessages)
    }

    func setFirstErrorIfNeeded(_ error: Error) {
        lock.lock()
        if storedError == nil {
            storedError = error
        }
        lock.unlock()
    }

    func firstError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}
