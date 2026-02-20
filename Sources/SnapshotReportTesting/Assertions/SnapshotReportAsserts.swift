import Foundation
import XCTest
import SnapshotReportCore
import SnapshotTesting

#if canImport(Testing)
import Testing
#endif

#if canImport(UIKit)
import UIKit
#endif

public enum MissingReferencePolicy: Sendable, Equatable {
    case recordOnMissingReference
    case fail
}

public struct SnapshotAssertionDefaults: Sendable, Equatable {
    public var device: SnapshotDevicePreset
    public var configuredOSMajorVersion: Int
    public var captureHeight: SnapshotCaptureHeight
    public var highContrastReport: Bool
    public var missingReferencePolicy: MissingReferencePolicy

    public init(
        device: SnapshotDevicePreset = .iPhoneSe,
        configuredOSMajorVersion: Int = SnapshotDevicePreset.defaultConfiguredOSMajorVersion,
        captureHeight: SnapshotCaptureHeight = .device,
        highContrastReport: Bool = false,
        missingReferencePolicy: MissingReferencePolicy = .recordOnMissingReference
    ) {
        self.device = device
        self.configuredOSMajorVersion = configuredOSMajorVersion
        self.captureHeight = captureHeight
        self.highContrastReport = highContrastReport
        self.missingReferencePolicy = missingReferencePolicy
    }
}

private final class _SnapshotAssertionDefaultsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = SnapshotAssertionDefaults()

    func set(_ defaults: SnapshotAssertionDefaults) {
        lock.lock()
        value = defaults
        lock.unlock()
    }

    func get() -> SnapshotAssertionDefaults {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private let _snapshotAssertionDefaultsBox = _SnapshotAssertionDefaultsBox()

public func configureSnapshotAssertionDefaults(_ defaults: SnapshotAssertionDefaults) {
    _snapshotAssertionDefaultsBox.set(defaults)
}

private func _snapshotAssertionDefaults() -> SnapshotAssertionDefaults {
    _snapshotAssertionDefaultsBox.get()
}

public enum SnapshotAppearanceConfiguration: String, CaseIterable, Sendable {
    case light
    case dark
    case highContrastLight
    case highContrastDark

    public static let defaultPair: [SnapshotAppearanceConfiguration] = [.light, .dark]
    public static let all: [SnapshotAppearanceConfiguration] = [.light, .dark, .highContrastLight, .highContrastDark]
    public static let reportOrder: [SnapshotAppearanceConfiguration] = [.highContrastLight, .light, .dark, .highContrastDark]

    public var nameSuffix: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        case .highContrastLight: return "high-contrast-light"
        case .highContrastDark: return "high-contrast-dark"
        }
    }

    #if canImport(UIKit)
    var traitCollection: UITraitCollection {
        switch self {
        case .light:
            return UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(accessibilityContrast: .normal)
            ])
        case .dark:
            return UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .dark),
                UITraitCollection(accessibilityContrast: .normal)
            ])
        case .highContrastLight:
            return UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(accessibilityContrast: .high)
            ])
        case .highContrastDark:
            return UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .dark),
                UITraitCollection(accessibilityContrast: .high)
            ])
        }
    }
    #endif
}

public func configureSnapshotReport(
    reportName: String = "Snapshot Tests",
    outputJSONPath: String? = nil,
    metadata: [String: String] = [:]
) {
    let defaultConfiguration = SnapshotReportRuntimeConfiguration.default()
    let path = outputJSONPath ?? defaultConfiguration.outputJSONPath
    let final = SnapshotReportRuntimeConfiguration(reportName: reportName, outputJSONPath: path, metadata: metadata)

    Task {
        await SnapshotReportRuntime.shared.configure(final)
        await SnapshotReportRuntime.shared.installObserverIfNeeded()
    }
}

@discardableResult
public func assertReportingSnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    suiteName: String? = nil,
    className: String? = nil,
    named: String? = nil,
    record: Bool = false,
    timeout: TimeInterval = 5,
    missingReferencePolicy: MissingReferencePolicy = .recordOnMissingReference,
    attachSuccessfulSnapshots: Bool = true,
    referenceURL: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) -> String? {
    let inferredSuite = suiteName ?? URL(fileURLWithPath: file.description).deletingPathExtension().lastPathComponent
    let inferredClass = className ?? inferredSuite

    return _assertReportingSnapshot(
        of: { try value() },
        as: snapshotting,
        suiteName: inferredSuite,
        className: inferredClass,
        named: named,
        record: record,
        timeout: timeout,
        missingReferencePolicy: missingReferencePolicy,
        attachSuccessfulSnapshots: attachSuccessfulSnapshots,
        referenceURL: referenceURL,
        file: file,
        testName: testName,
        line: line
    )
}

#if canImport(UIKit)
@discardableResult
public func assertSnapshot(
    of viewController: @autoclosure () throws -> UIViewController,
    device: SnapshotDevicePreset? = nil,
    configuredOSMajorVersion: Int? = nil,
    captureHeight: SnapshotCaptureHeight? = nil,
    highContrastReport: Bool? = nil,
    osMajorVersion: Int? = nil,
    appearances: [SnapshotAppearanceConfiguration]? = nil,
    suiteName: String? = nil,
    className: String? = nil,
    named: String? = nil,
    record: Bool = false,
    timeout: TimeInterval = 5,
    missingReferencePolicy: MissingReferencePolicy? = nil,
    diffing: any SnapshotImageDiffing = CoreImageDifferenceDiffing(),
    referenceURL: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) -> [String] {
    let defaults = _snapshotAssertionDefaults()
    let resolvedDevice = device ?? defaults.device
    let resolvedConfiguredOSMajorVersion = configuredOSMajorVersion ?? defaults.configuredOSMajorVersion
    let resolvedCaptureHeight = captureHeight ?? defaults.captureHeight
    let resolvedHighContrastReport = highContrastReport ?? defaults.highContrastReport
    let resolvedAppearances = appearances ?? (
        resolvedHighContrastReport
        ? SnapshotAppearanceConfiguration.reportOrder
        : SnapshotAppearanceConfiguration.defaultPair
    )
    let resolvedMissingReferencePolicy = missingReferencePolicy ?? defaults.missingReferencePolicy

    let runtimeMajor = osMajorVersion ?? ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    let deviceConfiguration = SnapshotDeviceConfiguration(
        preset: resolvedDevice,
        configuredOSMajorVersion: resolvedConfiguredOSMajorVersion,
        captureHeight: resolvedCaptureHeight
    )

    do {
        try deviceConfiguration.validateCompatibility(osMajorVersion: runtimeMajor)
    } catch {
        let message = "Snapshot device configuration error: \(error)"
        _recordFrameworkIssue(message, file: file, line: line)
        return [message]
    }

    let viewControllerValue: UIViewController
    do {
        viewControllerValue = try viewController()
    } catch {
        let message = "Failed to build UIViewController under test: \(error)"
        _recordFrameworkIssue(message, file: file, line: line)
        return [message]
    }

    var failures: [String] = []
    let baseConfig = deviceConfiguration.viewImageConfig()

    for appearance in resolvedAppearances {
        let snapshotName = [named, appearance.nameSuffix]
            .compactMap { $0 }
            .joined(separator: "-")

        let configWithTraits = ViewImageConfig(
            safeArea: baseConfig.safeArea,
            size: baseConfig.size,
            traits: UITraitCollection(traitsFrom: [baseConfig.traits, appearance.traitCollection])
        )

        let strategy = Snapshotting<UIViewController, UIImage>.image(
            on: configWithTraits,
            traits: appearance.traitCollection
        )

        let failure = _assertReportingSnapshot(
            of: { viewControllerValue },
            as: strategy,
            suiteName: suiteName ?? String(describing: type(of: viewControllerValue)),
            className: className ?? String(describing: type(of: viewControllerValue)),
            named: snapshotName,
            record: record,
            timeout: timeout,
            missingReferencePolicy: resolvedMissingReferencePolicy,
            attachSuccessfulSnapshots: true,
            imageDiffing: diffing,
            referenceURL: referenceURL,
            file: file,
            testName: testName,
            line: line
        )

        if let failure {
            failures.append("[\(appearance.rawValue)] \(failure)")
        }
    }

    return failures
}
#endif

public extension XCTestCase {
    func configureSnapshotAssertionDefaults(_ defaults: SnapshotAssertionDefaults) {
        SnapshotReportTesting.configureSnapshotAssertionDefaults(defaults)
    }

    func configureSnapshotReport(
        reportName: String = "Snapshot Tests",
        outputJSONPath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        SnapshotReportTesting.configureSnapshotReport(
            reportName: reportName,
            outputJSONPath: outputJSONPath,
            metadata: metadata
        )
    }

    @discardableResult
    func assertReportingSnapshot<Value, Format>(
        of value: @autoclosure () throws -> Value,
        as snapshotting: Snapshotting<Value, Format>,
        named: String? = nil,
        record: Bool = false,
        timeout: TimeInterval = 5,
        missingReferencePolicy: MissingReferencePolicy = .recordOnMissingReference,
        attachSuccessfulSnapshots: Bool = true,
        referenceURL: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) -> String? {
        _assertReportingSnapshot(
            of: { try value() },
            as: snapshotting,
            suiteName: String(describing: type(of: self)),
            className: String(describing: type(of: self)),
            named: named,
            record: record,
            timeout: timeout,
            missingReferencePolicy: missingReferencePolicy,
            attachSuccessfulSnapshots: attachSuccessfulSnapshots,
            referenceURL: referenceURL,
            file: file,
            testName: testName,
            line: line
        )
    }

    #if canImport(UIKit)
    @discardableResult
    func assertSnapshot(
        of viewController: @autoclosure () throws -> UIViewController,
        device: SnapshotDevicePreset? = nil,
        configuredOSMajorVersion: Int? = nil,
        captureHeight: SnapshotCaptureHeight? = nil,
        highContrastReport: Bool? = nil,
        osMajorVersion: Int? = nil,
        appearances: [SnapshotAppearanceConfiguration]? = nil,
        named: String? = nil,
        record: Bool = false,
        timeout: TimeInterval = 5,
        missingReferencePolicy: MissingReferencePolicy? = nil,
        diffing: any SnapshotImageDiffing = CoreImageDifferenceDiffing(),
        referenceURL: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) -> [String] {
        let value: UIViewController
        do {
            value = try viewController()
        } catch {
            let message = "Failed to build UIViewController under test: \(error)"
            _recordFrameworkIssue(message, file: file, line: line)
            return [message]
        }

        return SnapshotReportTesting.assertSnapshot(
            of: value,
            device: device,
            configuredOSMajorVersion: configuredOSMajorVersion,
            captureHeight: captureHeight,
            highContrastReport: highContrastReport,
            osMajorVersion: osMajorVersion,
            appearances: appearances,
            suiteName: String(describing: type(of: self)),
            className: String(describing: type(of: self)),
            named: named,
            record: record,
            timeout: timeout,
            missingReferencePolicy: missingReferencePolicy,
            diffing: diffing,
            referenceURL: referenceURL,
            file: file,
            testName: testName,
            line: line
        )
    }
    #endif
}

@discardableResult
private func _assertReportingSnapshot<Value, Format>(
    of value: () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    suiteName: String,
    className: String,
    named: String? = nil,
    record: Bool = false,
    timeout: TimeInterval,
    missingReferencePolicy: MissingReferencePolicy,
    attachSuccessfulSnapshots: Bool,
    imageDiffing: (any SnapshotImageDiffing)? = nil,
    referenceURL: String? = nil,
    file: StaticString,
    testName: String,
    line: UInt
) -> String? {
    let start = Date()
    let normalizedTestName = _normalize(testName: testName)

    let evaluated: Value
    do {
        evaluated = try value()
    } catch {
        let failureMessage = "Failed to build value under test: \(error)"
        _recordFrameworkIssue(failureMessage, file: file, line: line)
        Task {
            await SnapshotReportRuntime.shared.installObserverIfNeeded()
            await SnapshotReportRuntime.shared.record(
                suite: suiteName,
                test: normalizedTestName,
                className: className,
                duration: Date().timeIntervalSince(start),
                failure: failureMessage,
                referenceURL: referenceURL
            )
        }
        return failureMessage
    }

    let failureMessage = verifySnapshot(
        of: evaluated,
        as: snapshotting,
        named: named,
        record: record,
        timeout: timeout,
        file: file,
        testName: normalizedTestName,
        line: line
    )

    let treatedAsSuccess = _shouldTreatAsRecordedSuccess(
        failureMessage: failureMessage,
        missingReferencePolicy: missingReferencePolicy
    )

    let normalizedFailure = treatedAsSuccess ? nil : failureMessage
    if let normalizedFailure {
        _recordFrameworkIssue(normalizedFailure, file: file, line: line)
    }

    var attachments: [SnapshotAttachment] = []

    if let snapshotFileURL = _inferredSnapshotFileURL(
        file: file,
        testName: normalizedTestName,
        named: named,
        pathExtension: snapshotting.pathExtension
    ), FileManager.default.fileExists(atPath: snapshotFileURL.path) {
        if attachSuccessfulSnapshots || normalizedFailure != nil {
            attachments.append(
                SnapshotAttachment(
                    name: "Snapshot",
                    type: _attachmentType(for: snapshotFileURL.pathExtension),
                    path: snapshotFileURL.path
                )
            )
        }

        #if canImport(UIKit)
        if let imageSnapshotting = snapshotting as? Snapshotting<Value, UIImage>,
           let normalizedFailure,
           let actual = _materializeSnapshot(value: evaluated, snapshotting: imageSnapshotting, timeout: timeout),
           let actualData = actual.pngData() {
            // Always store the actual image so CLI odiff post-processing can use it.
            let actualURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("snapshot-actual-\(UUID().uuidString).png")
            try? actualData.write(to: actualURL)
            attachments.append(SnapshotAttachment(name: "Actual Snapshot", type: .png, path: actualURL.path))

            // CoreImage diff (only when a diffing strategy is provided).
            if let imageDiffing,
               let reference = UIImage(contentsOfFile: snapshotFileURL.path),
               let diffImage = imageDiffing.makeDiff(reference: reference, actual: actual),
               let diffData = diffImage.pngData() {
                let diffURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("snapshot-diff-\(UUID().uuidString).png")
                try? diffData.write(to: diffURL)
                attachments.append(
                    SnapshotAttachment(
                        name: "Advanced Diff",
                        type: .png,
                        path: diffURL.path
                    )
                )
            }

            // Keep failure text explicit when no diff text is embedded.
            if normalizedFailure.contains("difference") == false {
                attachments.append(
                    SnapshotAttachment(
                        name: "Failure Message",
                        type: .text,
                        path: _writeTextAttachment(contents: normalizedFailure)
                    )
                )
            }
        }
        #endif
    }

    let duration = Date().timeIntervalSince(start)
    Task {
        await SnapshotReportRuntime.shared.installObserverIfNeeded()
        await SnapshotReportRuntime.shared.record(
            suite: suiteName,
            test: normalizedTestName,
            className: className,
            duration: duration,
            failure: normalizedFailure,
            attachments: attachments,
            referenceURL: referenceURL
        )
    }

    return normalizedFailure
}

private func _normalize(testName: String) -> String {
    testName.replacingOccurrences(of: "()", with: "")
}

private func _sanitizePathComponent(_ value: String) -> String {
    value.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "-", options: .regularExpression)
}

private func _shouldTreatAsRecordedSuccess(
    failureMessage: String?,
    missingReferencePolicy: MissingReferencePolicy
) -> Bool {
    guard let failureMessage else { return false }

    if failureMessage.contains("Record mode is on. Automatically recorded snapshot") {
        return true
    }

    switch missingReferencePolicy {
    case .recordOnMissingReference:
        return failureMessage.contains("No reference was found on disk. Automatically recorded snapshot")
    case .fail:
        return false
    }
}

private func _attachmentType(for pathExtension: String) -> SnapshotAttachmentType {
    switch pathExtension.lowercased() {
    case "png": return .png
    case "txt", "text", "md": return .text
    case "dump": return .dump
    default: return .binary
    }
}

private func _inferredSnapshotFileURL(
    file: StaticString,
    testName: String,
    named: String?,
    pathExtension: String?
) -> URL? {
    let fileURL = URL(fileURLWithPath: file.description, isDirectory: false)
    let fileName = fileURL.deletingPathExtension().lastPathComponent
    let snapshotDirectory = fileURL
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent(fileName, isDirectory: true)

    let testNameSanitized = _sanitizePathComponent(testName)

    if let named, !named.isEmpty {
        var url = snapshotDirectory.appendingPathComponent("\(testNameSanitized).\(_sanitizePathComponent(named))")
        if let pathExtension {
            url = url.appendingPathExtension(pathExtension)
        }
        return url
    }

    guard let files = try? FileManager.default.contentsOfDirectory(
        at: snapshotDirectory,
        includingPropertiesForKeys: nil
    ) else {
        return nil
    }

    return files.first { $0.lastPathComponent.hasPrefix("\(testNameSanitized).") }
}

#if canImport(UIKit)
private func _materializeSnapshot<Value>(
    value: Value,
    snapshotting: Snapshotting<Value, UIImage>,
    timeout: TimeInterval
) -> UIImage? {
    let semaphore = DispatchSemaphore(value: 0)
    var output: UIImage?

    snapshotting.snapshot(value).run { image in
        output = image
        semaphore.signal()
    }

    let result = semaphore.wait(timeout: .now() + timeout)
    guard result == .success else { return nil }
    return output
}
#endif

private func _writeTextAttachment(contents: String) -> String {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("snapshot-text-\(UUID().uuidString).txt")
    try? contents.data(using: .utf8)?.write(to: url)
    return url.path
}

private func _recordFrameworkIssue(_ message: String, file: StaticString, line: UInt) {
    #if canImport(Testing)
    if Test.current != nil {
        Issue.record(
            Comment(rawValue: message),
            sourceLocation: SourceLocation(
                fileID: file.description,
                filePath: file.description,
                line: Int(line),
                column: 1
            )
        )
        return
    }
    #endif

    XCTFail(message, file: file, line: line)
}
