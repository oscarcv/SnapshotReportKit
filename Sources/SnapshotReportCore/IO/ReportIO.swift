import Foundation

public enum SnapshotReportError: Error, CustomStringConvertible {
    case invalidInput(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .writeFailed(let message):
            return "Write failed: \(message)"
        }
    }
}

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

    public static func loadReport(from fileURL: URL) throws -> SnapshotReport {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SnapshotReport.self, from: data)
    }

    public static func saveReport(_ report: SnapshotReport, to fileURL: URL) throws {
        let data = try encoder.encode(report)
        try data.write(to: fileURL)
    }
}
