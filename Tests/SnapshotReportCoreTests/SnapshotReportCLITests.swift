import Foundation
import Testing
@testable import snapshot_report

private final class TestLogStore: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    func removeAll() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}

@Test
func verboseFlagAndDiagnosticLogs() throws {
    let verboseOptions = try CLI.parse(arguments: ["--input", "/tmp/report.json", "--verbose"])
    #expect(verboseOptions.verbose)

    let defaultOptions = try CLI.parse(arguments: ["--input", "/tmp/report.json"])
    #expect(defaultOptions.verbose == false)

    let store = TestLogStore()

    CLIUI.resetForTesting()
    CLIUI.setWriterForTesting { line in
        store.append(line)
    }
    defer { CLIUI.resetForTesting() }

    CLIUI.setVerbose(false)
    CLIUI.step("Resolving input files")
    CLIUI.debug("Merged report: 2 tests (2 passed, 0 failed, 0 skipped)")
    CLIUI.success("Generated report html at /tmp/output")

    let nonVerboseLines = store.snapshot()
    #expect(nonVerboseLines.count == 1)
    #expect(nonVerboseLines[0] == "[snapshot-report] success: Generated report html at /tmp/output")

    store.removeAll()

    CLIUI.setVerbose(true)
    CLIUI.header("snapshot-report")
    CLIUI.step("Resolving input files")
    CLIUI.progress("XCResult 1/1: SnapshotTests.xcresult")
    CLIUI.debug("Total processing time: 0.123s")
    CLIUI.success("Generated report html at /tmp/output")

    #expect(store.snapshot() == [
        "[snapshot-report] snapshot-report",
        "[snapshot-report] step: Resolving input files",
        "[snapshot-report] progress: XCResult 1/1: SnapshotTests.xcresult",
        "[snapshot-report] debug: Total processing time: 0.123s",
        "[snapshot-report] success: Generated report html at /tmp/output",
    ])
}

@Test
func defaultAutomaticJobsUsesHalfProcessorCount() {
    #expect(CLI.defaultAutomaticJobs(processorCount: 1) == 1)
    #expect(CLI.defaultAutomaticJobs(processorCount: 2) == 1)
    #expect(CLI.defaultAutomaticJobs(processorCount: 7) == 3)
    #expect(CLI.defaultAutomaticJobs(processorCount: 8) == 4)
}

@Test
func parseJobsModeDefaultsToAutoAndSupportsOverride() throws {
    let autoOptions = try CLI.parse(arguments: ["--input", "/tmp/report.json"])
    switch autoOptions.jobsMode {
    case .auto(let totalCores):
        #expect(totalCores >= 1)
        #expect(autoOptions.jobs == CLI.defaultAutomaticJobs(processorCount: totalCores))
    case .manual:
        Issue.record("Expected auto jobs mode when --jobs is not provided")
    }

    let manualOptions = try CLI.parse(arguments: ["--input", "/tmp/report.json", "--jobs", "4"])
    #expect(manualOptions.jobs == 4)
    switch manualOptions.jobsMode {
    case .auto:
        Issue.record("Expected manual jobs mode when --jobs is provided")
    case .manual:
        break
    }
}
