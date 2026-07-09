import XCTest
import UIKit
@testable import GD_MangaReader

final class SeriesThumbnailStoreTests: XCTestCase {

    // Helper to create a dummy UIImage backed by CGImage
    private func createDummyImage(width: Int, height: Int) -> UIImage? {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)

        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        // Fill with a color just to have something in the context
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }

    func testCropLeadingPage_WithValidImage_ReturnsCroppedLeftHalf() {
        // Arrange
        let originalWidth = 400
        let originalHeight = 300
        guard let image = createDummyImage(width: originalWidth, height: originalHeight) else {
            XCTFail("Failed to create dummy image")
            return
        }

        // Act
        let croppedImage = SeriesThumbnailStore.cropLeadingPage(of: image)

        // Assert
        XCTAssertNotNil(croppedImage)
        guard let cgCropped = croppedImage?.cgImage else {
            XCTFail("Cropped image should be backed by CGImage")
            return
        }

        XCTAssertEqual(cgCropped.width, originalWidth / 2)
        XCTAssertEqual(cgCropped.height, originalHeight)
    }

    func testCropLeadingPage_WithInvalidImage_ReturnsNil() {
        // Arrange
        // Create an image backed by CIImage, which means `image.cgImage` will be nil
        let ciImage = CIImage(color: .red)
        let imageWithoutCGImage = UIImage(ciImage: ciImage)

        // Act
        let croppedImage = SeriesThumbnailStore.cropLeadingPage(of: imageWithoutCGImage)

        // Assert
        XCTAssertNil(croppedImage, "Cropping an image without CGImage should return nil")
    }
}
