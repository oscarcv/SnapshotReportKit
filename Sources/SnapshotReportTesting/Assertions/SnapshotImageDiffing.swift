import Foundation

#if canImport(UIKit)
import UIKit
import CoreImage

/// Protocol for generating visual diffs between reference and actual images.
public protocol SnapshotImageDiffing: Sendable {
    /// Creates a diff image.
    /// - Parameters:
    ///   - reference: Reference snapshot image.
    ///   - actual: Actual snapshot image.
    /// - Returns: A rendered diff image, or `nil` when diffing fails.
    func makeDiff(reference: UIImage, actual: UIImage) -> UIImage?
}

/// CoreImage-based image diff implementation using `CIDifferenceBlendMode`.
public struct CoreImageDifferenceDiffing: SnapshotImageDiffing {
    /// Creates a CoreImage-based differ.
    public init() {}

    /// Creates a boosted visual diff image from two `UIImage` values.
    public func makeDiff(reference: UIImage, actual: UIImage) -> UIImage? {
        guard
            let refCG = reference.cgImage,
            let actualCG = actual.cgImage
        else {
            return nil
        }

        let ciRef = CIImage(cgImage: refCG)
        let ciActual = CIImage(cgImage: actualCG)

        let extent = ciRef.extent.intersection(ciActual.extent)
        guard !extent.isEmpty else { return nil }

        guard
            let diff = CIFilter(name: "CIDifferenceBlendMode", parameters: [
                kCIInputImageKey: ciActual,
                kCIInputBackgroundImageKey: ciRef,
            ])?.outputImage?.cropped(to: extent),
            let boosted = CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: diff,
                kCIInputSaturationKey: 2.0,
                kCIInputContrastKey: 2.5,
                kCIInputBrightnessKey: 0.05,
            ])?.outputImage
        else {
            return nil
        }

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(boosted, from: boosted.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
#endif

#if !canImport(UIKit)
/// Marker protocol on non-UIKit platforms where image diffing is unavailable.
public protocol SnapshotImageDiffing: Sendable {}

/// No-op implementation placeholder for non-UIKit platforms.
public struct CoreImageDifferenceDiffing: SnapshotImageDiffing {
    /// Creates a no-op differ.
    public init() {}
}
#endif
