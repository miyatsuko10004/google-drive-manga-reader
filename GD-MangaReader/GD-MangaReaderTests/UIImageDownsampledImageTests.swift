import XCTest
import UIKit
@testable import GD_MangaReader

final class UIImageDownsampledImageTests: XCTestCase {

    // Helper function to create a dummy image data for testing
    private func createDummyImageData(size: CGSize, color: UIColor = .red) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Use 1.0 scale so the pixel size matches the points
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }

    // Helper function to save dummy image data to a temporary URL
    private func createDummyImageURL(size: CGSize, color: UIColor = .blue) -> URL? {
        guard let data = createDummyImageData(size: size, color: color) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    func testDownsampledImageFromData_ValidData() {
        // Arrange
        let originalSize = CGSize(width: 1000, height: 1000)
        let targetSize = CGSize(width: 100, height: 100)

        guard let imageData = createDummyImageData(size: originalSize) else {
            XCTFail("Failed to create dummy image data")
            return
        }

        // Act
        let downsampledImage = UIImage.downsampledImage(from: imageData, to: targetSize)

        // Assert
        XCTAssertNotNil(downsampledImage, "Downsampled image should not be nil")

        // Due to rendering and scaling details, we just check if it's significantly smaller than original
        // or close to target size. The exact dimensions might vary based on aspect ratio preserving behavior.
        if let size = downsampledImage?.size {
            XCTAssertTrue(size.width <= targetSize.width && size.height <= targetSize.height, "Downsampled image size (\(size)) should be less than or equal to target size (\(targetSize))")
        }
    }

    func testDownsampledImageFromData_InvalidData() {
        // Arrange
        let invalidData = Data("Not an image".utf8)
        let targetSize = CGSize(width: 100, height: 100)

        // Act
        let downsampledImage = UIImage.downsampledImage(from: invalidData, to: targetSize)

        // Assert
        XCTAssertNil(downsampledImage, "Downsampled image should be nil for invalid data")
    }

    func testDownsampledImageFromURL_ValidURL() {
        // Arrange
        let originalSize = CGSize(width: 800, height: 600)
        let targetSize = CGSize(width: 150, height: 150)

        guard let imageURL = createDummyImageURL(size: originalSize) else {
            XCTFail("Failed to create dummy image URL")
            return
        }

        defer {
            // Clean up temporary file
            try? FileManager.default.removeItem(at: imageURL)
        }

        // Act
        let downsampledImage = UIImage.downsampledImage(from: imageURL, to: targetSize)

        // Assert
        XCTAssertNotNil(downsampledImage, "Downsampled image should not be nil")

        if let size = downsampledImage?.size {
            XCTAssertTrue(size.width <= targetSize.width && size.height <= targetSize.height, "Downsampled image size (\(size)) should be less than or equal to target size (\(targetSize))")
        }
    }

    func testDownsampledImageFromURL_InvalidURL() {
        // Arrange
        let invalidURL = URL(fileURLWithPath: "/path/to/non/existent/image.png")
        let targetSize = CGSize(width: 100, height: 100)

        // Act
        let downsampledImage = UIImage.downsampledImage(from: invalidURL, to: targetSize)

        // Assert
        XCTAssertNil(downsampledImage, "Downsampled image should be nil for invalid URL")
    }
}
