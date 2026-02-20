import Foundation
import XCTest
import SnapshotReportCore

/// Runtime configuration for automatic per-run report persistence.
public struct SnapshotReportRuntimeConfiguration: Sendable {
    /// Display name for generated reports.
    public var reportName: String
    /// Output JSON path for the current run.
    public var outputJSONPath: String
    /// Report metadata appended during persistence.
    public var metadata: [String: String]

    /// Creates a runtime configuration.
    public init(reportName: String, outputJSONPath: String, metadata: [String: String] = [:]) {
        self.reportName = reportName
        self.outputJSONPath = outputJSONPath
        self.metadata = metadata
    }

    /// Resolves default configuration from process environment variables.
    public static func `default`() -> SnapshotReportRuntimeConfiguration {
        let env = ProcessInfo.processInfo.environment

        let output: String
        if let explicit = env["SNAPSHOT_REPORT_OUTPUT"], !explicit.isEmpty {
            output = explicit
        } else if let outputDir = env["SNAPSHOT_REPORT_OUTPUT_DIR"], !outputDir.isEmpty {
            let runFileName = makeRunFileName(reportName: env["SNAPSHOT_REPORT_NAME"] ?? "Snapshot Tests")
            output = URL(fileURLWithPath: outputDir)
                .appendingPathComponent(runFileName)
                .path
        } else if let srcRoot = env["SRCROOT"], !srcRoot.isEmpty {
            output = URL(fileURLWithPath: srcRoot)
                .appendingPathComponent(".artifacts/snapshot-runs")
                .appendingPathComponent(makeRunFileName(reportName: env["SNAPSHOT_REPORT_NAME"] ?? "Snapshot Tests"))
                .path
        } else {
            output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("snapshot-runs")
                .appendingPathComponent(makeRunFileName(reportName: env["SNAPSHOT_REPORT_NAME"] ?? "Snapshot Tests"))
                .path
        }

        let reportName = env["SNAPSHOT_REPORT_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? "Snapshot Tests"

        var metadata: [String: String] = [:]
        if let scheme = env["SCHEME_NAME"], !scheme.isEmpty { metadata["scheme"] = scheme }
        if let branch = env["GIT_BRANCH"], !branch.isEmpty { metadata["branch"] = branch }
        if let testPlan = env["TEST_PLAN_NAME"], !testPlan.isEmpty { metadata["testPlan"] = testPlan }
        if let target = env["TARGET_NAME"], !target.isEmpty { metadata["target"] = target }
        if let bundle = Bundle.main.bundleIdentifier, !bundle.isEmpty { metadata["bundle"] = bundle }

        return .init(reportName: reportName, outputJSONPath: output, metadata: metadata)
    }

    private static func makeRunFileName(reportName: String) -> String {
        let safeName = reportName
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "-", options: .regularExpression)
        return "\(safeName)-\(ProcessInfo.processInfo.processIdentifier).json"
    }
}

/// Global runtime coordinator that collects test results and persists report JSON.
public actor SnapshotReportRuntime {
    /// Shared singleton runtime.
    public static let shared = SnapshotReportRuntime()

    private var configuration = SnapshotReportRuntimeConfiguration.default()
    private var collector: SnapshotReportCollector
    private var installedObserver = false
    private var hasRecords = false

    /// Creates a runtime with default configuration.
    public init() {
        self.collector = SnapshotReportCollector(reportName: SnapshotReportRuntimeConfiguration.default().reportName)
    }

    /// Applies a new runtime configuration and resets current collector state.
    public func configure(_ configuration: SnapshotReportRuntimeConfiguration) {
        self.configuration = configuration
        self.collector = SnapshotReportCollector(reportName: configuration.reportName)
        self.hasRecords = false
    }

    /// Installs XCTest observation once, on the main actor, to flush data at bundle end.
    public func installObserverIfNeeded() async {
        guard !installedObserver else { return }
        installedObserver = true
        await SnapshotReportObserverRegistry.shared.installIfNeeded()
    }

    /// Records one assertion result and persists the current in-memory report snapshot.
    public func record(
        suite: String,
        test: String,
        className: String,
        duration: TimeInterval,
        failure: String?,
        attachments: [SnapshotAttachment] = [],
        referenceURL: String? = nil
    ) async {
        hasRecords = true

        if let failure {
            await collector.recordFailure(
                suite: suite,
                test: test,
                className: className,
                duration: duration,
                message: failure,
                attachments: attachments,
                referenceURL: referenceURL
            )
        } else {
            await collector.recordSuccess(
                suite: suite,
                test: test,
                className: className,
                duration: duration,
                attachments: attachments,
                referenceURL: referenceURL
            )
        }

        await persistCurrentReport()
    }

    /// Flushes final state to disk, merging with existing output when present.
    public func flush() async {
        // Record operations are scheduled via Task from synchronous assertion APIs.
        // Wait briefly so those tasks can hop onto the actor before concluding there is no data.
        var waitsRemaining = 20
        while !hasRecords && waitsRemaining > 0 {
            waitsRemaining -= 1
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        guard hasRecords else { return }

        // Give in-flight record calls a short quiescence window before final aggregation.
        try? await Task.sleep(nanoseconds: 150_000_000)

        let destination = URL(fileURLWithPath: configuration.outputJSONPath)
        let dir = destination.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let currentReport = await collector.buildReport(metadata: configuration.metadata)

            if FileManager.default.fileExists(atPath: destination.path) {
                let existing = try SnapshotReportIO.loadReport(from: destination)
                let merged = SnapshotReportAggregator.merge(
                    reports: [existing, currentReport],
                    name: currentReport.name
                )
                try SnapshotReportIO.saveReport(merged, to: destination)
            } else {
                try await collector.writeJSON(to: destination, metadata: configuration.metadata)
            }
        } catch {
            fputs("SnapshotReportRuntime flush error: \(error)\n", stderr)
        }
    }

    private func persistCurrentReport() async {
        let destination = URL(fileURLWithPath: configuration.outputJSONPath)
        let dir = destination.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try await collector.writeJSON(to: destination, metadata: configuration.metadata)
        } catch {
            fputs("SnapshotReportRuntime persist error: \(error)\n", stderr)
        }
    }
}

@MainActor
final class SnapshotReportObserverRegistry {
    static let shared = SnapshotReportObserverRegistry()

    private var observer: SnapshotReportBundleObserver?

    private init() {}

    func installIfNeeded() {
        guard observer == nil else { return }
        let observer = SnapshotReportBundleObserver()
        self.observer = observer
        XCTestObservationCenter.shared.addTestObserver(observer)
    }
}

final class SnapshotReportBundleObserver: NSObject, XCTestObservation {
    func testBundleDidFinish(_ testBundle: Bundle) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await SnapshotReportRuntime.shared.flush()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
    }
}
