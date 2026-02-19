import Foundation

public struct SnapshotReport: Codable, Sendable {
    public var name: String
    public var generatedAt: Date
    public var suites: [SnapshotSuite]
    public var metadata: [String: String]

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

public struct SnapshotSummary: Codable, Sendable {
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let duration: TimeInterval
}

public struct SnapshotSuite: Codable, Sendable {
    public var name: String
    public var tests: [SnapshotTestCase]

    public init(name: String, tests: [SnapshotTestCase]) {
        self.name = name
        self.tests = tests
    }
}

public struct SnapshotTestCase: Codable, Sendable {
    public var id: String
    public var name: String
    public var className: String
    public var status: SnapshotStatus
    public var duration: TimeInterval
    public var failure: SnapshotFailure?
    public var attachments: [SnapshotAttachment]

    public init(
        id: String = UUID().uuidString,
        name: String,
        className: String,
        status: SnapshotStatus,
        duration: TimeInterval,
        failure: SnapshotFailure? = nil,
        attachments: [SnapshotAttachment] = []
    ) {
        self.id = id
        self.name = name
        self.className = className
        self.status = status
        self.duration = duration
        self.failure = failure
        self.attachments = attachments
    }
}

public enum SnapshotStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
}

public struct SnapshotFailure: Codable, Sendable {
    public var message: String
    public var file: String?
    public var line: Int?
    public var diff: String?

    public init(message: String, file: String? = nil, line: Int? = nil, diff: String? = nil) {
        self.message = message
        self.file = file
        self.line = line
        self.diff = diff
    }
}

public struct SnapshotAttachment: Codable, Sendable {
    public var name: String
    public var type: SnapshotAttachmentType
    public var path: String

    public init(name: String, type: SnapshotAttachmentType, path: String) {
        self.name = name
        self.type = type
        self.path = path
    }
}

public enum SnapshotAttachmentType: String, Codable, Sendable {
    case png
    case text
    case dump
    case binary

    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .text, .dump: return "text/plain"
        case .binary: return "application/octet-stream"
        }
    }
}
