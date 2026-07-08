import XCTest
import UIKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GD_MangaReader

final class SeriesThumbnailStoreTests: XCTestCase {

    // Test directory
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // Helper to create a dummy image with specific size and EXIF orientation
    private func createTestImage(width: Int, height: Int, orientation: UInt32, filename: String) -> URL? {
        let url = tempDirectory.appendingPathComponent(filename)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            return nil
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(destination)

        return url
    }

    func testIsWideImage_normalPortrait() {
        // Normal portrait image, width < height
        guard let url = createTestImage(width: 1000, height: 1500, orientation: 1, filename: "portrait.jpg") else {
            XCTFail("Failed to create test image")
            return
        }

        let isWide = SeriesThumbnailStore.isWideImage(at: url)
        XCTAssertFalse(isWide)
    }

    func testIsWideImage_normalWide() {
        // Normal wide image, width > height * 1.2
        guard let url = createTestImage(width: 2000, height: 1000, orientation: 1, filename: "wide.jpg") else {
            XCTFail("Failed to create test image")
            return
        }

        let isWide = SeriesThumbnailStore.isWideImage(at: url)
        XCTAssertTrue(isWide)
    }

    func testIsWideImage_rotated90Portrait() {
        // Originally wide (2000x1000), but rotated 90 degrees (orientation 6)
        // Displayed as portrait (1000x2000), should not be wide
        guard let url = createTestImage(width: 2000, height: 1000, orientation: 6, filename: "rotated_portrait.jpg") else {
            XCTFail("Failed to create test image")
            return
        }

        let isWide = SeriesThumbnailStore.isWideImage(at: url)
        XCTAssertFalse(isWide)
    }

    func testIsWideImage_rotated90Wide() {
        // Originally portrait (1000x2000), but rotated 90 degrees (orientation 8)
        // Displayed as wide (2000x1000), should be wide
        guard let url = createTestImage(width: 1000, height: 2000, orientation: 8, filename: "rotated_wide.jpg") else {
            XCTFail("Failed to create test image")
            return
        }

        let isWide = SeriesThumbnailStore.isWideImage(at: url)
        XCTAssertTrue(isWide)
    }

    func testIsWideImage_invalidURL() {
        let url = tempDirectory.appendingPathComponent("nonexistent.jpg")
        let isWide = SeriesThumbnailStore.isWideImage(at: url)
        XCTAssertFalse(isWide)
    }
}
