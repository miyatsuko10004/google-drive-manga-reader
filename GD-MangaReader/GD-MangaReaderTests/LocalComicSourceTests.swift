//
//  LocalComicSourceTests.swift
//  GD-MangaReaderTests
//

import XCTest
import CoreGraphics
import UniformTypeIdentifiers
import ImageIO
@testable import GD_MangaReader

final class LocalComicSourceTests: XCTestCase {

    var testComicPath: String!
    var testComicDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        testComicPath = "TestComic_" + UUID().uuidString
        testComicDirectory = LocalStorageService.shared.comicsDirectory.appendingPathComponent(testComicPath)

        // Create directory for dummy files
        try FileManager.default.createDirectory(at: testComicDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up dummy directory
        if FileManager.default.fileExists(atPath: testComicDirectory.path) {
            try FileManager.default.removeItem(at: testComicDirectory)
        }

        try super.tearDownWithError()
    }

    // Helper to create an actual image file with specified dimensions
    private func createDummyImage(fileName: String, width: Int, height: Int) throws -> URL {
        let fileURL = testComicDirectory.appendingPathComponent(fileName)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        // Fill with dummy color
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImageDestination"])
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize CGImageDestination"])
        }

        return fileURL
    }

    func testIsWidePage_OutOfBounds_ReturnsFalse() async throws {
        let comic = LocalComic(
            title: "Test Comic",
            driveFileId: "test_drive_id",
            localPath: testComicPath,
            imageFileNames: ["1.jpg", "2.jpg"] // Only 2 items
        )
        let source = LocalComicSource(comic: comic)

        // Act
        let isWideNegative = await source.isWidePage(at: -1)
        let isWideExceeds = await source.isWidePage(at: 2)

        // Assert
        XCTAssertFalse(isWideNegative, "Negative index should return false")
        XCTAssertFalse(isWideExceeds, "Index >= count should return false")
    }

    func testIsWidePage_MissingFile_ReturnsFalse() async throws {
        let comic = LocalComic(
            title: "Test Comic",
            driveFileId: "test_drive_id",
            localPath: testComicPath,
            imageFileNames: ["missing.jpg"] // File not on disk
        )
        let source = LocalComicSource(comic: comic)

        // Act
        let isWide = await source.isWidePage(at: 0)

        // Assert
        XCTAssertFalse(isWide, "Missing file should handle gracefully and return false")
    }

    func testIsWidePage_NormalPage_ReturnsFalse() async throws {
        // Arrange
        let _ = try createDummyImage(fileName: "normal.jpg", width: 1000, height: 1500)

        let comic = LocalComic(
            title: "Test Comic",
            driveFileId: "test_drive_id",
            localPath: testComicPath,
            imageFileNames: ["normal.jpg"]
        )
        let source = LocalComicSource(comic: comic)

        // Act
        let isWide = await source.isWidePage(at: 0)

        // Assert
        XCTAssertFalse(isWide, "width=1000, height=1500 is a portrait image and should not be wide (1000 < 1500 * 1.2 = 1800)")
    }

    func testIsWidePage_WidePage_ReturnsTrue() async throws {
        // Arrange
        // Threshold: width > height * 1.2
        // If height = 1000, threshold = 1200
        // Width = 1201 > 1200
        let _ = try createDummyImage(fileName: "wide.jpg", width: 1201, height: 1000)

        let comic = LocalComic(
            title: "Test Comic",
            driveFileId: "test_drive_id",
            localPath: testComicPath,
            imageFileNames: ["wide.jpg"]
        )
        let source = LocalComicSource(comic: comic)

        // Act
        let isWide = await source.isWidePage(at: 0)

        // Assert
        XCTAssertTrue(isWide, "width=1201, height=1000 is wide enough (1201 > 1000 * 1.2 = 1200)")
    }

    func testIsWidePage_ExactThreshold_ReturnsFalse() async throws {
        // Arrange
        // Width strictly equal to threshold: 1200 == 1000 * 1.2
        let _ = try createDummyImage(fileName: "exact.jpg", width: 1200, height: 1000)

        let comic = LocalComic(
            title: "Test Comic",
            driveFileId: "test_drive_id",
            localPath: testComicPath,
            imageFileNames: ["exact.jpg"]
        )
        let source = LocalComicSource(comic: comic)

        // Act
        let isWide = await source.isWidePage(at: 0)

        // Assert
        XCTAssertFalse(isWide, "Strict inequality (>) means exactly 1.2 ratio should be false")
    }
}
