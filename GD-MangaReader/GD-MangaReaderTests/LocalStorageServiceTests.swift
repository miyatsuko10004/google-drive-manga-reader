import XCTest
@testable import GD_MangaReader

final class LocalStorageServiceTests: XCTestCase {

    var service: LocalStorageService!

    override func setUp() {
        super.setUp()
        service = LocalStorageService.shared
        try? service.clearAllComics()
        service.clearTempDirectory()
    }

    override func tearDown() {
        try? service.clearAllComics()
        service.clearTempDirectory()
        service = nil
        super.tearDown()
    }

    func testLoadAndSaveComics() throws {
        // Initially empty
        let initialComics = try service.loadComics()
        XCTAssertTrue(initialComics.isEmpty)

        // Save a comic
        let comic = LocalComic(title: "Test Comic", driveFileId: "123", localPath: "test_comic")
        try service.saveComics([comic])

        // Load and verify
        let loadedComics = try service.loadComics()
        XCTAssertEqual(loadedComics.count, 1)
        XCTAssertEqual(loadedComics.first?.title, "Test Comic")
        XCTAssertEqual(loadedComics.first?.driveFileId, "123")
    }

    func testAddComic() throws {
        let comic1 = LocalComic(title: "Comic 1", driveFileId: "id_1", localPath: "path1")
        try service.addComic(comic1)

        var loadedComics = try service.loadComics()
        XCTAssertEqual(loadedComics.count, 1)

        // Add a new comic
        let comic2 = LocalComic(title: "Comic 2", driveFileId: "id_2", localPath: "path2")
        try service.addComic(comic2)
        loadedComics = try service.loadComics()
        XCTAssertEqual(loadedComics.count, 2)

        // Add a comic with existing driveFileId (should update)
        let comic1Updated = LocalComic(title: "Comic 1 Updated", driveFileId: "id_1", localPath: "path1")
        try service.addComic(comic1Updated)
        loadedComics = try service.loadComics()
        XCTAssertEqual(loadedComics.count, 2)
        XCTAssertEqual(loadedComics.first(where: { $0.driveFileId == "id_1" })?.title, "Comic 1 Updated")
    }

    func testUpdateComic() throws {
        let comic = LocalComic(title: "Initial", driveFileId: "id", localPath: "path")
        try service.addComic(comic)

        var loadedComics = try service.loadComics()
        guard var savedComic = loadedComics.first else {
            XCTFail("Comic should be saved")
            return
        }

        savedComic.lastReadPage = 10
        try service.updateComic(savedComic)

        loadedComics = try service.loadComics()
        XCTAssertEqual(loadedComics.first?.lastReadPage, 10)
    }

    func testDeleteComic() throws {
        let comic = LocalComic(title: "To Delete", driveFileId: "delete_id", localPath: "delete_path")
        try service.addComic(comic)

        XCTAssertEqual(try service.loadComics().count, 1)

        try service.deleteComic(comic)
        XCTAssertTrue(try service.loadComics().isEmpty)
    }

    func testFindComic() throws {
        let comic = LocalComic(title: "Find Me", driveFileId: "find_id", localPath: "find_path")
        try service.addComic(comic)

        let found = try service.findComic(byDriveFileId: "find_id")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Find Me")

        let notFound = try service.findComic(byDriveFileId: "unknown")
        XCTAssertNil(notFound)
    }

    func testCreateComicDirectory() throws {
        let dirURL = try service.createComicDirectory(name: "Test Manga <Invalid>")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirURL.path))
        XCTAssertEqual(dirURL.lastPathComponent, "Test Manga _Invalid_")
    }

    func testTempFileOperations() throws {
        let tempURL = service.createTempFilePath(extension: "jpg")
        XCTAssertEqual(tempURL.pathExtension, "jpg")

        // Create a dummy file
        try Data("dummy".utf8).write(to: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        service.deleteTempFile(at: tempURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testClearTempDirectory() throws {
        let tempURL = service.createTempFilePath(extension: "txt")
        try Data("dummy".utf8).write(to: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        service.clearTempDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.tempDirectory.path))
    }

    func testGetImageFiles() throws {
        let dir = try service.createComicDirectory(name: "ImageTest")

        let image1 = dir.appendingPathComponent("01.jpg")
        let image2 = dir.appendingPathComponent("02.png")
        let text1 = dir.appendingPathComponent("info.txt")

        try Data("dummy".utf8).write(to: image1)
        try Data("dummy".utf8).write(to: image2)
        try Data("dummy".utf8).write(to: text1)

        let images = service.getImageFiles(in: dir)
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.contains("01.jpg"))
        XCTAssertTrue(images.contains("02.png"))
        XCTAssertFalse(images.contains("info.txt"))
    }

    func testCalculateSize() throws {
        let dir = try service.createComicDirectory(name: "SizeTest")
        let file1 = dir.appendingPathComponent("file1.txt")
        let file2 = dir.appendingPathComponent("file2.txt")

        let data1 = Data(repeating: 0, count: 1024)
        let data2 = Data(repeating: 0, count: 2048)

        try data1.write(to: file1)
        try data2.write(to: file2)

        let comic = LocalComic(title: "SizeTest", driveFileId: "size_id", localPath: "SizeTest")

        let size = service.calculateSize(of: comic)
        XCTAssertEqual(size, 3072) // 1024 + 2048
    }

    func testCalculateStorageUsage() throws {
        let initialUsage = service.calculateStorageUsage()

        let dir = try service.createComicDirectory(name: "UsageTest")
        let file1 = dir.appendingPathComponent("file.bin")
        try Data(repeating: 0, count: 4096).write(to: file1)

        let newUsage = service.calculateStorageUsage()
        XCTAssertEqual(newUsage - initialUsage, 4096)
    }
}
