import Foundation

/// Capture height policy for view snapshots.
public enum SnapshotCaptureHeight: Sendable, Equatable {
    /// Use the preset device height.
    case device
    /// Larger-than-device height suitable for long screens.
    case large
    /// Very tall capture for complete/scroll-like content.
    case complete
    /// Explicit capture height in points.
    case points(Double)
}

/// Supported device presets used by snapshot assertions.
public enum SnapshotDevicePreset: String, CaseIterable, Sendable {
    case iPhoneSe
    case iPhone11Pro
    case iPhone13
    case iPhone13ProMax

    /// OS major versions accepted by runtime validation.
    public static let allowedOSMajorVersions: Set<Int> = [15, 16, 17, 18, 26]
    /// Default configured OS major version used by assertions.
    public static let defaultConfiguredOSMajorVersion: Int = 26
}

/// Snapshot device/runtime configuration used by assertion helpers.
public struct SnapshotDeviceConfiguration: Sendable, Equatable {
    /// Device preset.
    public var preset: SnapshotDevicePreset
    /// Expected runtime iOS major version.
    public var configuredOSMajorVersion: Int
    /// Capture height policy.
    public var captureHeight: SnapshotCaptureHeight

    /// Creates a snapshot device configuration.
    public init(
        preset: SnapshotDevicePreset = .iPhoneSe,
        configuredOSMajorVersion: Int = SnapshotDevicePreset.defaultConfiguredOSMajorVersion,
        captureHeight: SnapshotCaptureHeight = .device
    ) {
        self.preset = preset
        self.configuredOSMajorVersion = configuredOSMajorVersion
        self.captureHeight = captureHeight
    }

    /// Validates that the configured runtime version is allowed and matches the current runtime.
    /// - Parameter osMajorVersion: Current runtime OS major version.
    public func validateCompatibility(osMajorVersion: Int) throws {
        guard SnapshotDevicePreset.allowedOSMajorVersions.contains(configuredOSMajorVersion) else {
            throw SnapshotDeviceConfigurationError.unsupportedRuntime(
                device: preset.rawValue,
                osMajorVersion: osMajorVersion,
                configuredOSMajorVersion: configuredOSMajorVersion
            )
        }

        guard configuredOSMajorVersion == osMajorVersion else {
            throw SnapshotDeviceConfigurationError.unsupportedRuntime(
                device: preset.rawValue,
                osMajorVersion: osMajorVersion,
                configuredOSMajorVersion: configuredOSMajorVersion
            )
        }
    }
}

/// Errors thrown while validating `SnapshotDeviceConfiguration`.
public enum SnapshotDeviceConfigurationError: Error, CustomStringConvertible, Sendable {
    /// Device/runtime pair is unsupported or mismatched.
    case unsupportedRuntime(device: String, osMajorVersion: Int, configuredOSMajorVersion: Int)

    /// Human-readable error description.
    public var description: String {
        switch self {
        case .unsupportedRuntime(let device, let osMajorVersion, let configuredOSMajorVersion):
            let supported = SnapshotDevicePreset.allowedOSMajorVersions.sorted().map(String.init).joined(separator: ", ")
            return "Incompatible snapshot device/runtime: \(device) on iOS \(osMajorVersion).x is unsupported. Configured iOS major version: \(configuredOSMajorVersion). Allowed versions: \(supported)."
        }
    }
}

#if canImport(UIKit)
import UIKit
import SnapshotTesting

public extension SnapshotDevicePreset {
    func baseViewImageConfig() -> ViewImageConfig {
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
}

public extension SnapshotDeviceConfiguration {
    func viewImageConfig() -> ViewImageConfig {
        let base = preset.baseViewImageConfig()

        guard let size = base.size else {
            return base
        }

        return ViewImageConfig(
            safeArea: base.safeArea,
            size: CGSize(width: size.width, height: captureHeight.resolved(baseHeight: size.height)),
            traits: base.traits
        )
    }
}

private extension SnapshotCaptureHeight {
    func resolved(baseHeight: CGFloat) -> CGFloat {
        switch self {
        case .device:
            return baseHeight
        case .large:
            return max(baseHeight * 1.6, 1_500)
        case .complete:
            return max(baseHeight * 2.6, 2_500)
        case .points(let points):
            return max(CGFloat(points), baseHeight)
        }
    }
}
#endif
