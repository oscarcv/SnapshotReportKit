import Foundation

#if canImport(UIKit)
import UIKit
import SnapshotTesting

public enum SnapshotDevicePreset: String, CaseIterable, Sendable {
    case iPhoneSe
    case iPhone11Pro
    case iPhone13
    case iPhone13ProMax

    public func viewImageConfig() -> ViewImageConfig {
        switch self {
        case .iPhoneSe:
            return .iPhoneSe(.portrait)
        case .iPhone11Pro:
            // Closest available config in SnapshotTesting for this form factor.
            return .iPhoneX(.portrait)
        case .iPhone13:
            return .iPhone13(.portrait)
        case .iPhone13ProMax:
            return .iPhone13ProMax(.portrait)
        }
    }

    public func validateCompatibility(osMajorVersion: Int) throws {
        let supportedRange: ClosedRange<Int>

        switch self {
        case .iPhoneSe:
            supportedRange = 13...18
        case .iPhone11Pro:
            supportedRange = 13...17
        case .iPhone13, .iPhone13ProMax:
            supportedRange = 15...18
        }

        guard supportedRange.contains(osMajorVersion) else {
            throw SnapshotDeviceConfigurationError.unsupportedRuntime(
                device: rawValue,
                osMajorVersion: osMajorVersion,
                supportedRange: supportedRange
            )
        }
    }
}

public enum SnapshotDeviceConfigurationError: Error, CustomStringConvertible, Sendable {
    case unsupportedRuntime(device: String, osMajorVersion: Int, supportedRange: ClosedRange<Int>)

    public var description: String {
        switch self {
        case .unsupportedRuntime(let device, let osMajorVersion, let supportedRange):
            return "Incompatible snapshot device/runtime: \(device) on iOS \(osMajorVersion).x is unsupported. Supported range: iOS \(supportedRange.lowerBound)...\(supportedRange.upperBound)."
        }
    }
}
#endif
