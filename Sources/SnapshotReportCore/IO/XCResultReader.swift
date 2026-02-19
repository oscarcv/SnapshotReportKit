import Foundation

/// Reads an `.xcresult` bundle produced by `xcodebuild test` and converts it
/// into a `SnapshotReport` by shelling out to `xcrun xcresulttool`.
public struct XCResultReader: Sendable {
    public init() {}

    /// Parses the given `.xcresult` bundle and returns a `SnapshotReport`.
    public func read(xcresultPath: URL) throws -> SnapshotReport {
        let topLevel = try fetchJSON(
            args: ["xcresulttool", "get", "--format", "json", "--path", xcresultPath.path]
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
        guard let actions = invocationRecord["actions"] as? [[String: Any]] else {
            return []
        }

        var suites: [SnapshotSuite] = []

        for action in actions {
            guard
                let actionResult = action["actionResult"] as? [String: Any],
                let testsRef = actionResult["testsRef"] as? [String: Any],
                let refID = value(from: testsRef, key: "id")
            else { continue }

            let summariesJSON = try fetchJSON(
                args: ["xcresulttool", "get", "--format", "json", "--id", refID, "--path", xcresultPath.path]
            )

            let extracted = try extractSuites(from: summariesJSON, xcresultPath: xcresultPath)
            suites.append(contentsOf: extracted)
        }

        return suites
    }

    private func extractSuites(from summariesJSON: [String: Any], xcresultPath: URL) throws -> [SnapshotSuite] {
        guard let summaries = summariesJSON["summaries"] as? [[String: Any]] else {
            return []
        }

        var result: [SnapshotSuite] = []

        for summary in summaries {
            guard let testableSummaries = summary["testableSummaries"] as? [[String: Any]] else { continue }
            for testableSummary in testableSummaries {
                let suiteName = value(from: testableSummary, key: "name") ?? "Unknown Suite"
                guard let tests = testableSummary["tests"] as? [[String: Any]] else { continue }
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
            if let subtests = node["subtests"] as? [[String: Any]] {
                cases.append(contentsOf: try extractTestCases(from: subtests, xcresultPath: xcresultPath))
                continue
            }

            let name = value(from: node, key: "name") ?? "Unknown Test"
            let identifier = value(from: node, key: "identifier") ?? name
            let statusString = value(from: node, key: "testStatus") ?? "Failure"
            let status = mapStatus(statusString)
            let duration = (node["duration"] as? [String: Any]).flatMap { d in
                (d["_value"] as? String).flatMap(Double.init)
            } ?? 0

            var failure: SnapshotFailure?
            var attachments: [SnapshotAttachment] = []

            if status == .failed {
                if let summaries = node["failureSummaries"] as? [[String: Any]],
                   let firstSummary = summaries.first {
                    let message = value(from: firstSummary, key: "message") ?? "Test failed"
                    let file = value(from: firstSummary, key: "fileName")
                    let lineString = (firstSummary["lineNumber"] as? [String: Any])
                        .flatMap { v in (v["_value"] as? String).flatMap(Int.init) }
                    failure = SnapshotFailure(message: message, file: file, line: lineString)
                }

                // Export the first PNG attachment found in activity summaries
                if let activitySummaries = node["activitySummaries"] as? [[String: Any]] {
                    if let attachment = firstPNGAttachment(
                        in: activitySummaries,
                        xcresultPath: xcresultPath
                    ) {
                        attachments.append(attachment)
                    }
                }
            }

            cases.append(SnapshotTestCase(
                name: name,
                className: identifier,
                status: status,
                duration: duration,
                failure: failure,
                attachments: attachments
            ))
        }

        return cases
    }

    private func firstPNGAttachment(in activitySummaries: [[String: Any]], xcresultPath: URL) -> SnapshotAttachment? {
        for activity in activitySummaries {
            guard let activityAttachments = activity["attachments"] as? [[String: Any]] else { continue }
            for att in activityAttachments {
                guard
                    let uniformTypeID = value(from: att, key: "uniformTypeIdentifier"),
                    uniformTypeID == "public.png",
                    let payloadRef = att["payloadRef"] as? [String: Any],
                    let payloadID = value(from: payloadRef, key: "id")
                else { continue }

                let destURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("xcresult-\(payloadID)-\(UUID().uuidString).png")

                do {
                    try xcrun(args: [
                        "xcresulttool", "export",
                        "--type", "file",
                        "--id", payloadID,
                        "--output-path", destURL.path,
                        "--path", xcresultPath.path
                    ])
                    return SnapshotAttachment(name: "Snapshot", type: .png, path: destURL.path)
                } catch {
                    continue
                }
            }
        }
        return nil
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
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCResultReaderError.xcrunFailed(args: args, exitCode: process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
