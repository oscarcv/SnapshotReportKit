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
