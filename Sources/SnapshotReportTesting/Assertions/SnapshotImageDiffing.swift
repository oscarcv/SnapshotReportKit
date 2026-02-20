import Foundation

#if canImport(UIKit)
import UIKit
import CoreImage

public protocol SnapshotImageDiffing: Sendable {
    func makeDiff(reference: UIImage, actual: UIImage) -> UIImage?
}

public struct CoreImageDifferenceDiffing: SnapshotImageDiffing {
    public init() {}

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
public protocol SnapshotImageDiffing: Sendable {}

public struct CoreImageDifferenceDiffing: SnapshotImageDiffing {
    public init() {}
}
#endif
