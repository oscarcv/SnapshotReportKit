import Foundation

/// Errors produced by snapshot report input/output operations.
public enum SnapshotReportError: Error, CustomStringConvertible {
    /// Provided input is invalid or missing required data.
    case invalidInput(String)
    /// Writing report output failed.
    case writeFailed(String)

    /// Human-readable description of the error.
    public var description: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .writeFailed(let message):
            return "Write failed: \(message)"
        }
    }
}

/// Utilities for reading and writing report JSON files.
public enum SnapshotReportIO {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// Loads a `SnapshotReport` from JSON.
    /// - Parameter fileURL: Path to the JSON report file.
    /// - Returns: Decoded report.
    public static func loadReport(from fileURL: URL) throws -> SnapshotReport {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SnapshotReport.self, from: data)
    }

    /// Writes a `SnapshotReport` to JSON.
    /// - Parameters:
    ///   - report: Report value to serialize.
    ///   - fileURL: Destination file path.
    public static func saveReport(_ report: SnapshotReport, to fileURL: URL) throws {
        let data = try encoder.encode(report)
        try data.write(to: fileURL)
    }
}
