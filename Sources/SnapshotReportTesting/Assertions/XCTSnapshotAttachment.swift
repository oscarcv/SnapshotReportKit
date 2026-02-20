import Foundation
import XCTest

public enum XCTSnapshotAttachmentKind: String, Sendable, Codable {
    case snapshot
    case failure
    case diff
    case manifest
}

public struct SnapshotAssertionManifest: Sendable, Codable {
    public let schemaVersion: Int
    public let assertID: String
    public let suiteName: String
    public let className: String
    public let testName: String
    public let snapshotName: String
    public let status: String
    public let device: String?
    public let configuredOSMajorVersion: Int?
    public let runtimeOSVersion: String
    public let captureHeight: String?
    public let appearance: String?
    public let highContrast: Bool?
    public let referenceURL: String?

    public init(
        schemaVersion: Int = 1,
        assertID: String,
        suiteName: String,
        className: String,
        testName: String,
        snapshotName: String,
        status: String,
        device: String? = nil,
        configuredOSMajorVersion: Int? = nil,
        runtimeOSVersion: String,
        captureHeight: String? = nil,
        appearance: String? = nil,
        highContrast: Bool? = nil,
        referenceURL: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.assertID = assertID
        self.suiteName = suiteName
        self.className = className
        self.testName = testName
        self.snapshotName = snapshotName
        self.status = status
        self.device = device
        self.configuredOSMajorVersion = configuredOSMajorVersion
        self.runtimeOSVersion = runtimeOSVersion
        self.captureHeight = captureHeight
        self.appearance = appearance
        self.highContrast = highContrast
        self.referenceURL = referenceURL
    }
}

@MainActor
public enum XCTSnapshotAttachmentBuilder {
    public static func makeName(assertID: String, kind: XCTSnapshotAttachmentKind, label: String) -> String {
        let safeLabel = sanitize(label)
        return "SnapshotReport|\(assertID)|\(kind.rawValue)|\(safeLabel)"
    }

    public static func addPNGAttachment(
        filePath: String,
        assertID: String,
        kind: XCTSnapshotAttachmentKind,
        label: String
    ) {
        guard let data = FileManager.default.contents(atPath: filePath) else { return }
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = makeName(assertID: assertID, kind: kind, label: label)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    public static func addManifestAttachment(
        _ manifest: SnapshotAssertionManifest
    ) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = makeName(assertID: manifest.assertID, kind: .manifest, label: manifest.snapshotName)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func add(_ attachment: XCTAttachment) {
        XCTContext.runActivity(named: "SnapshotReport Attachments") { activity in
            activity.add(attachment)
        }
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "-", options: .regularExpression)
    }
}
