import Foundation

/// Runs the `odiff` binary for each failed test that has both a `"Snapshot"`
/// (reference) attachment and an `"Actual Snapshot"` (captured) attachment.
/// Appends a new `"odiff"` attachment with the highlighted diff image.
public struct OdiffProcessor: Sendable {
    public let odiffBinaryPath: String

    public init(odiffBinaryPath: String = "odiff") {
        self.odiffBinaryPath = odiffBinaryPath
    }

    /// Returns a new `SnapshotReport` with odiff attachments appended to
    /// each failed test case that has both reference and actual PNGs.
    public func process(report: SnapshotReport) -> SnapshotReport {
        var suites = report.suites
        for suiteIdx in suites.indices {
            for caseIdx in suites[suiteIdx].tests.indices {
                let test = suites[suiteIdx].tests[caseIdx]
                guard test.status == .failed else { continue }
                suites[suiteIdx].tests[caseIdx] = processTest(test)
            }
        }
        return SnapshotReport(
            name: report.name,
            generatedAt: report.generatedAt,
            suites: suites,
            metadata: report.metadata
        )
    }

    private func processTest(_ test: SnapshotTestCase) -> SnapshotTestCase {
        guard
            let referenceAttachment = test.attachments.first(where: { $0.name == "Snapshot" }),
            let actualAttachment = test.attachments.first(where: { $0.name == "Actual Snapshot" })
        else { return test }

        let diffOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("odiff-\(test.id)-\(UUID().uuidString).png")

        runOdiff(
            reference: referenceAttachment.path,
            actual: actualAttachment.path,
            output: diffOutputURL.path
        )

        guard FileManager.default.fileExists(atPath: diffOutputURL.path) else {
            return test
        }

        var updated = test
        updated.attachments.append(
            SnapshotAttachment(name: "odiff", type: .png, path: diffOutputURL.path)
        )
        return updated
    }

    /// Shells out to the odiff binary.
    /// odiff exits 0 when images are identical (no output file written),
    /// 1 when a diff is produced (output file written), or 2 on error.
    private func runOdiff(reference: String, actual: String, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: odiffBinaryPath)
        process.arguments = [reference, actual, output]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
