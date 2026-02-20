import Foundation
import SnapshotReportCore

/// Reads an `.xcresult` bundle produced by `xcodebuild test` and converts it
/// into a `SnapshotReport` by shelling out to `xcrun xcresulttool`.
public struct XCResultReader: Sendable {
    public init() {}

    /// Parses the given `.xcresult` bundle and returns a `SnapshotReport`.
    public func read(xcresultPath: URL) throws -> SnapshotReport {
        let topLevel = try fetchJSON(
            args: ["xcresulttool", "get", "object", "--legacy", "--format", "json", "--path", xcresultPath.path]
        )
        let suites = try parseSuites(from: topLevel, xcresultPath: xcresultPath)
        return SnapshotReport(
            name: xcresultPath.deletingPathExtension().lastPathComponent,
            generatedAt: Date(),
            suites: suites
        )
    }

    // MARK: - Parsing

    private func parseSuites(from invocationRecord: [String: Any], xcresultPath: URL) throws -> [SnapshotSuite] {
        let actions = arrayValues(from: invocationRecord, key: "actions")
        guard !actions.isEmpty else { return [] }

        var suites: [SnapshotSuite] = []

        for action in actions {
            guard
                let actionResult = action["actionResult"] as? [String: Any],
                let testsRef = actionResult["testsRef"] as? [String: Any],
                let refID = value(from: testsRef, key: "id")
            else { continue }

            let summariesJSON = try fetchJSON(
                args: ["xcresulttool", "get", "object", "--legacy", "--format", "json", "--id", refID, "--path", xcresultPath.path]
            )

            let extracted = try extractSuites(from: summariesJSON, xcresultPath: xcresultPath)
            suites.append(contentsOf: extracted)
        }

        if suites.isEmpty {
            suites = parseIssueFallback(from: actions)
        }

        return suites
    }

    private func parseIssueFallback(from actions: [[String: Any]]) -> [SnapshotSuite] {
        var grouped: [String: [SnapshotTestCase]] = [:]

        for action in actions {
            guard
                let actionResult = action["actionResult"] as? [String: Any],
                let issues = actionResult["issues"] as? [String: Any]
            else { continue }

            for summary in arrayValues(from: issues, key: "testFailureSummaries") {
                let fullName = value(from: summary, key: "testCaseName") ?? "UnknownTest.test"
                let parts = fullName.replacingOccurrences(of: "()", with: "").split(separator: ".", maxSplits: 1).map(String.init)
                let className = parts.first ?? "UnknownTest"
                let testName = parts.count > 1 ? parts[1] : fullName
                let message = value(from: summary, key: "message") ?? "Test failed"
                let (file, line) = parseLocation(from: summary)

                let testCase = SnapshotTestCase(
                    name: testName,
                    className: className,
                    status: .failed,
                    duration: 0,
                    failure: SnapshotFailure(message: message, file: file, line: line),
                    attachments: []
                )

                grouped[className, default: []].append(testCase)
            }
        }

        return grouped
            .sorted(by: { $0.key < $1.key })
            .map { SnapshotSuite(name: $0.key, tests: $0.value) }
    }

    private func extractSuites(from summariesJSON: [String: Any], xcresultPath: URL) throws -> [SnapshotSuite] {
        let summaries = arrayValues(from: summariesJSON, key: "summaries")
        guard !summaries.isEmpty else {
            return []
        }

        var result: [SnapshotSuite] = []

        for summary in summaries {
            let testableSummaries = arrayValues(from: summary, key: "testableSummaries")
            guard !testableSummaries.isEmpty else { continue }
            for testableSummary in testableSummaries {
                let suiteName = value(from: testableSummary, key: "name") ?? "Unknown Suite"
                let tests = arrayValues(from: testableSummary, key: "tests")
                guard !tests.isEmpty else { continue }
                let testCases = try extractTestCases(from: tests, xcresultPath: xcresultPath)
                if !testCases.isEmpty {
                    result.append(SnapshotSuite(name: suiteName, tests: testCases))
                }
            }
        }

        return result
    }

    private func extractTestCases(from nodes: [[String: Any]], xcresultPath: URL) throws -> [SnapshotTestCase] {
        var cases: [SnapshotTestCase] = []

        for node in nodes {
            // Recurse into groups
            let subtests = arrayValues(from: node, key: "subtests")
            if !subtests.isEmpty {
                cases.append(contentsOf: try extractTestCases(from: subtests, xcresultPath: xcresultPath))
                continue
            }

            let name = (value(from: node, key: "name") ?? "Unknown Test").replacingOccurrences(of: "()", with: "")
            let identifier = value(from: node, key: "identifier") ?? name
            let className = identifier.split(separator: "/").first.map(String.init) ?? identifier
            let statusString = value(from: node, key: "testStatus") ?? "Failure"
            let status = mapStatus(statusString)
            let duration = doubleValue(from: node, key: "duration") ?? 0

            var failure: SnapshotFailure?
            var attachments: [SnapshotAttachment] = []

            // ActionTestMetadata nodes require dereferencing summaryRef for details.
            var detailsNode = node
            if let summaryRef = node["summaryRef"] as? [String: Any],
               let summaryID = value(from: summaryRef, key: "id") {
                detailsNode = try fetchJSON(
                    args: ["xcresulttool", "get", "object", "--legacy", "--format", "json", "--id", summaryID, "--path", xcresultPath.path]
                )
            }

            let activitySummaries = arrayValues(from: detailsNode, key: "activitySummaries")
            if !activitySummaries.isEmpty {
                attachments = exportAttachments(in: activitySummaries, xcresultPath: xcresultPath)
            }

            if status == .passed, attachments.isEmpty {
                attachments = inferReferenceAttachments(
                    for: name,
                    className: className,
                    xcresultPath: xcresultPath
                )
            }

            if status == .failed {
                if let firstSummary = arrayValues(from: detailsNode, key: "failureSummaries").first {
                    let message = value(from: firstSummary, key: "message") ?? "Test failed"
                    let file = value(from: firstSummary, key: "fileName")
                    let lineString = intValue(from: firstSummary, key: "lineNumber")
                    failure = SnapshotFailure(message: message, file: file, line: lineString)
                }
            }

            cases.append(SnapshotTestCase(
                name: name,
                className: className,
                status: status,
                duration: duration,
                failure: failure,
                attachments: attachments
            ))
        }

        return cases
    }

    private func inferReferenceAttachments(
        for testName: String,
        className: String,
        xcresultPath: URL
    ) -> [SnapshotAttachment] {
        guard let workspaceRoot = findWorkspaceRoot(startingAt: xcresultPath) else { return [] }

        let candidateRoots = [
            workspaceRoot.appendingPathComponent("examples/lib/Tests", isDirectory: true),
            workspaceRoot.appendingPathComponent("Tests", isDirectory: true)
        ]

        let fm = FileManager.default
        let prefix = "\(testName)."
        var matches: [URL] = []

        for root in candidateRoots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let path = fileURL.path
                guard path.contains("/__Snapshots__/\(className)/") else { continue }
                guard fileURL.pathExtension.lowercased() == "png" else { continue }
                guard fileURL.lastPathComponent.hasPrefix(prefix) else { continue }
                matches.append(fileURL)
            }
        }

        matches.sort { $0.lastPathComponent < $1.lastPathComponent }

        return matches.map { url in
            let filename = url.deletingPathExtension().lastPathComponent
            let label = String(filename.dropFirst(prefix.count))
            return SnapshotAttachment(name: label, type: .png, path: url.path)
        }
    }

    private func findWorkspaceRoot(startingAt xcresultPath: URL) -> URL? {
        var current = xcresultPath.deletingLastPathComponent()
        let fm = FileManager.default

        // xcresult is usually in <root>/.artifacts/xcresult, so climb until Package.swift is found.
        for _ in 0..<8 {
            if fm.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    private func exportAttachments(in activitySummaries: [[String: Any]], xcresultPath: URL) -> [SnapshotAttachment] {
        var exported: [SnapshotAttachment] = []

        for activity in activitySummaries {
            let activityAttachments = arrayValues(from: activity, key: "attachments")
            guard !activityAttachments.isEmpty else { continue }
            for att in activityAttachments {
                guard
                    let uniformTypeID = value(from: att, key: "uniformTypeIdentifier"),
                    uniformTypeID == "public.png",
                    let payloadRef = att["payloadRef"] as? [String: Any],
                    let payloadID = value(from: payloadRef, key: "id")
                else { continue }

                let baseFilename = value(from: att, key: "filename") ?? "\(payloadID).png"
                let destURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("xcresult-\(UUID().uuidString)-\(baseFilename)")

                do {
                    try xcrun(args: [
                        "xcresulttool", "export", "object", "--legacy",
                        "--type", "file",
                        "--id", payloadID,
                        "--output-path", destURL.path,
                        "--path", xcresultPath.path
                    ])
                    let rawName = (value(from: att, key: "name") ?? "Attachment").lowercased()
                    let mappedName: String
                    switch rawName {
                    case "reference":
                        mappedName = "Snapshot"
                    case "failure":
                        mappedName = "Actual Snapshot"
                    case "difference":
                        mappedName = "Diff"
                    default:
                        mappedName = value(from: att, key: "name") ?? "Attachment"
                    }
                    exported.append(SnapshotAttachment(name: mappedName, type: .png, path: destURL.path))
                } catch {
                    continue
                }
            }
        }
        return exported
    }

    private func mapStatus(_ xcStatus: String) -> SnapshotStatus {
        switch xcStatus.lowercased() {
        case "success": return .passed
        case "failure": return .failed
        case "skipped": return .skipped
        default: return .failed
        }
    }

    // MARK: - xcresulttool typed JSON helper

    /// xcresulttool uses a typed JSON format where scalar values appear as
    /// `{ "_type": { "_name": "String" }, "_value": "actual value" }`.
    /// This helper unwraps the `_value` field.
    private func value(from dict: [String: Any], key: String) -> String? {
        guard let entry = dict[key] as? [String: Any] else { return nil }
        return entry["_value"] as? String
    }

    private func arrayValues(from dict: [String: Any], key: String) -> [[String: Any]] {
        guard
            let entry = dict[key] as? [String: Any],
            let values = entry["_values"] as? [[String: Any]]
        else { return [] }
        return values
    }

    private func intValue(from dict: [String: Any], key: String) -> Int? {
        guard let entry = dict[key] as? [String: Any] else { return nil }
        return (entry["_value"] as? String).flatMap(Int.init)
    }

    private func doubleValue(from dict: [String: Any], key: String) -> Double? {
        guard let entry = dict[key] as? [String: Any] else { return nil }
        return (entry["_value"] as? String).flatMap(Double.init)
    }

    private func parseLocation(from summary: [String: Any]) -> (String?, Int?) {
        guard
            let location = summary["documentLocationInCreatingWorkspace"] as? [String: Any],
            let rawURL = value(from: location, key: "url"),
            let url = URL(string: rawURL),
            let fragment = url.fragment
        else { return (nil, nil) }

        let line = fragment
            .split(separator: "&")
            .first(where: { $0.hasPrefix("StartingLineNumber=") })
            .flatMap { Int($0.split(separator: "=").last ?? "") }

        return (url.path.isEmpty ? nil : url.path, line)
    }

    // MARK: - Process helpers

    private func xcrun(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCResultReaderError.xcrunFailed(args: args, exitCode: process.terminationStatus)
        }
    }

    private func fetchJSON(args: [String]) throws -> [String: Any] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCResultReaderError.xcrunFailed(args: args, exitCode: process.terminationStatus)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XCResultReaderError.unparseableOutput
        }
        return json
    }
}

public enum XCResultReaderError: Error, CustomStringConvertible {
    case xcrunFailed(args: [String], exitCode: Int32)
    case unparseableOutput

    public var description: String {
        switch self {
        case .xcrunFailed(let args, let exitCode):
            return "xcrun \(args.joined(separator: " ")) failed with exit code \(exitCode)"
        case .unparseableOutput:
            return "Could not parse xcresulttool JSON output"
        }
    }
}
