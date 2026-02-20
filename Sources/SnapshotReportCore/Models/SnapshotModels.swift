import Foundation

/// Root model that represents a full snapshot test report.
public struct SnapshotReport: Codable, Sendable {
    /// Display name of the report.
    public var name: String
    /// Timestamp when the report was generated.
    public var generatedAt: Date
    /// Grouped test suites included in the report.
    public var suites: [SnapshotSuite]
    /// Arbitrary report-level metadata (branch, scheme, etc.).
    public var metadata: [String: String]

    /// Creates a report value.
    /// - Parameters:
    ///   - name: Display name for the report.
    ///   - generatedAt: Generation date.
    ///   - suites: Suites to include.
    ///   - metadata: Optional metadata key-value pairs.
    public init(
        name: String,
        generatedAt: Date = Date(),
        suites: [SnapshotSuite],
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.generatedAt = generatedAt
        self.suites = suites
        self.metadata = metadata
    }

    /// Aggregated totals derived from all test cases in `suites`.
    public var summary: SnapshotSummary {
        let tests = suites.flatMap(\.tests)
        return SnapshotSummary(
            total: tests.count,
            passed: tests.filter { $0.status == .passed }.count,
            failed: tests.filter { $0.status == .failed }.count,
            skipped: tests.filter { $0.status == .skipped }.count,
            duration: tests.reduce(0) { $0 + $1.duration }
        )
    }
}

/// Computed aggregate metrics for a snapshot report.
public struct SnapshotSummary: Codable, Sendable {
    /// Total number of test cases.
    public let total: Int
    /// Number of passing test cases.
    public let passed: Int
    /// Number of failing test cases.
    public let failed: Int
    /// Number of skipped test cases.
    public let skipped: Int
    /// Sum of test durations in seconds.
    public let duration: TimeInterval
}

/// A logical suite of snapshot test cases.
public struct SnapshotSuite: Codable, Sendable {
    /// Suite name.
    public var name: String
    /// Tests in the suite.
    public var tests: [SnapshotTestCase]

    /// Creates a suite.
    /// - Parameters:
    ///   - name: Suite name.
    ///   - tests: Test cases in the suite.
    public init(name: String, tests: [SnapshotTestCase]) {
        self.name = name
        self.tests = tests
    }
}

/// Single snapshot assertion result.
public struct SnapshotTestCase: Codable, Sendable {
    /// Stable unique identifier for the test entry.
    public var id: String
    /// Test method name.
    public var name: String
    /// Test class/type name.
    public var className: String
    /// Final status of the test.
    public var status: SnapshotStatus
    /// Duration in seconds.
    public var duration: TimeInterval
    /// Failure details when status is `.failed`.
    public var failure: SnapshotFailure?
    /// Attachments associated with the test.
    public var attachments: [SnapshotAttachment]
    /// Optional URL to design/reference documentation.
    public var referenceURL: String?

    /// Creates a test case entry.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a random UUID.
    ///   - name: Test method name.
    ///   - className: Test class/type name.
    ///   - status: Final status.
    ///   - duration: Duration in seconds.
    ///   - failure: Optional failure payload.
    ///   - attachments: Attachments for the test.
    ///   - referenceURL: Optional design reference URL.
    public init(
        id: String = UUID().uuidString,
        name: String,
        className: String,
        status: SnapshotStatus,
        duration: TimeInterval,
        failure: SnapshotFailure? = nil,
        attachments: [SnapshotAttachment] = [],
        referenceURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.className = className
        self.status = status
        self.duration = duration
        self.failure = failure
        self.attachments = attachments
        self.referenceURL = referenceURL
    }
}

/// Lifecycle status of a snapshot test case.
public enum SnapshotStatus: String, Codable, Sendable {
    /// Test completed successfully.
    case passed
    /// Test completed with a mismatch/failure.
    case failed
    /// Test was skipped.
    case skipped
}

/// Failure payload for a failed snapshot test.
public struct SnapshotFailure: Codable, Sendable {
    /// Human-readable failure message.
    public var message: String
    /// Source file where failure occurred.
    public var file: String?
    /// Source line where failure occurred.
    public var line: Int?
    /// Optional textual diff payload.
    public var diff: String?

    /// Creates a failure payload.
    /// - Parameters:
    ///   - message: Failure message.
    ///   - file: Optional source file path.
    ///   - line: Optional source line number.
    ///   - diff: Optional textual diff content.
    public init(message: String, file: String? = nil, line: Int? = nil, diff: String? = nil) {
        self.message = message
        self.file = file
        self.line = line
        self.diff = diff
    }
}

/// Attachment linked to a test case.
public struct SnapshotAttachment: Codable, Sendable {
    /// Attachment display name.
    public var name: String
    /// Attachment media/log type.
    public var type: SnapshotAttachmentType
    /// Attachment path on disk or relative output path.
    public var path: String

    /// Creates an attachment entry.
    /// - Parameters:
    ///   - name: Display name.
    ///   - type: Attachment type.
    ///   - path: Path to attachment content.
    public init(name: String, type: SnapshotAttachmentType, path: String) {
        self.name = name
        self.type = type
        self.path = path
    }
}

/// Supported attachment media categories.
public enum SnapshotAttachmentType: String, Codable, Sendable {
    /// PNG image.
    case png
    /// UTF-8 text content.
    case text
    /// Structured dump content serialized as text.
    case dump
    /// Raw binary payload.
    case binary

    /// MIME type used when exporting this attachment in XML/HTML.
    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .text, .dump: return "text/plain"
        case .binary: return "application/octet-stream"
        }
    }
}
