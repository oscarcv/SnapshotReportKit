import Foundation
import XCTest
import SnapshotTesting

#if canImport(UIKit)
import UIKit
#endif

public enum SnapshotAppearanceConfiguration: String, CaseIterable, Sendable {
    case light
    case dark
    case highContrastLight
    case highContrastDark

    public static let defaultPair: [SnapshotAppearanceConfiguration] = [.light, .dark]
    public static let all: [SnapshotAppearanceConfiguration] = [.light, .dark, .highContrastLight, .highContrastDark]

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

public extension XCTestCase {
    func configureSnapshotReport(
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
    func assertReportingSnapshot<Value, Format>(
        of value: @autoclosure () throws -> Value,
        as snapshotting: Snapshotting<Value, Format>,
        named: String? = nil,
        record: Bool = false,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) -> String? {
        let start = Date()
        let suite = String(describing: type(of: self))
        let normalizedTestName = normalize(testName: testName)

        let evaluated: Value
        do {
            evaluated = try value()
        } catch {
            let failureMessage = "Failed to build value under test: \(error)"
            XCTFail(failureMessage, file: file, line: line)
            Task {
                await SnapshotReportRuntime.shared.installObserverIfNeeded()
                await SnapshotReportRuntime.shared.record(
                    suite: suite,
                    test: normalizedTestName,
                    className: suite,
                    duration: Date().timeIntervalSince(start),
                    failure: failureMessage
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

        if let failureMessage {
            XCTFail(failureMessage, file: file, line: line)
        }

        let duration = Date().timeIntervalSince(start)
        Task {
            await SnapshotReportRuntime.shared.installObserverIfNeeded()
            await SnapshotReportRuntime.shared.record(
                suite: suite,
                test: normalizedTestName,
                className: suite,
                duration: duration,
                failure: failureMessage
            )
        }

        return failureMessage
    }

    #if canImport(UIKit)
    @discardableResult
    func assertReportingSnapshotAppearances(
        of viewController: @autoclosure () throws -> UIViewController,
        on config: ViewImageConfig = .iPhoneSe,
        appearances: [SnapshotAppearanceConfiguration] = SnapshotAppearanceConfiguration.defaultPair,
        named: String? = nil,
        record: Bool = false,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) -> [String] {
        var failures: [String] = []

        let value: UIViewController
        do {
            value = try viewController()
        } catch {
            let message = "Failed to build UIViewController under test: \(error)"
            XCTFail(message, file: file, line: line)
            return [message]
        }

        for appearance in appearances {
            let snapshotName = [named, appearance.nameSuffix]
                .compactMap { $0 }
                .joined(separator: "-")

            let strategy = Snapshotting<UIViewController, UIImage>.image(
                on: config,
                traits: appearance.traitCollection
            )

            if let failure = assertReportingSnapshot(
                of: value,
                as: strategy,
                named: snapshotName,
                record: record,
                timeout: timeout,
                file: file,
                testName: testName,
                line: line
            ) {
                failures.append("[\(appearance.rawValue)] \(failure)")
            }
        }

        return failures
    }

    @discardableResult
    func assertSnapshot(
        of viewController: @autoclosure () throws -> UIViewController,
        on config: ViewImageConfig = .iPhoneSe,
        appearances: [SnapshotAppearanceConfiguration] = SnapshotAppearanceConfiguration.defaultPair,
        named: String? = nil,
        record: Bool = false,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) -> [String] {
        let built: UIViewController
        do {
            built = try viewController()
        } catch {
            let message = "Failed to build UIViewController under test: \(error)"
            XCTFail(message, file: file, line: line)
            return [message]
        }

        assertReportingSnapshotAppearances(
            of: built,
            on: config,
            appearances: appearances,
            named: named,
            record: record,
            timeout: timeout,
            file: file,
            testName: testName,
            line: line
        )
    }
    #endif

    private func normalize(testName: String) -> String {
        testName.replacingOccurrences(of: "()", with: "")
    }
}
