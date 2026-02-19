import Foundation

public enum SnapshotReportAggregator {
    public static func merge(reports: [SnapshotReport], name: String? = nil) -> SnapshotReport {
        guard let first = reports.first else {
            return SnapshotReport(name: name ?? "Snapshot Report", generatedAt: Date(), suites: [])
        }

        var mergedSuites: [String: SnapshotSuite] = [:]
        var metadata = first.metadata

        for report in reports {
            for (key, value) in report.metadata {
                metadata[key] = value
            }

            for suite in report.suites {
                if var existing = mergedSuites[suite.name] {
                    existing.tests.append(contentsOf: suite.tests)
                    mergedSuites[suite.name] = existing
                } else {
                    mergedSuites[suite.name] = suite
                }
            }
        }

        let suites = mergedSuites.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return SnapshotReport(name: name ?? first.name, generatedAt: Date(), suites: suites, metadata: metadata)
    }
}
