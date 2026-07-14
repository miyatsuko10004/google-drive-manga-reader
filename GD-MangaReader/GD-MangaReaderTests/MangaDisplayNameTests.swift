import XCTest
@testable import GD_MangaReader

final class MangaDisplayNameTests: XCTestCase {

    // MARK: - Folder format: 作品名[作者名]

    func testParsing_FolderFormat_ExtractsTitleAndAuthor() {
        let displayName = MangaDisplayName(parsing: "ワンピース[尾田栄一郎]")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
        XCTAssertNil(displayName.volume)
    }

    // MARK: - Both leading and trailing brackets

    func testParsing_LeadingAndTrailingBrackets_PrefersTrailingAuthorTag() {
        // Folder convention puts the author at the end; a leading tag like
        // a release-group marker must stay part of the title.
        let displayName = MangaDisplayName(parsing: "[HQ]鬼滅の刃[吾峠呼世晴]")

        XCTAssertEqual(displayName.title, "[HQ]鬼滅の刃")
        XCTAssertEqual(displayName.author, "吾峠呼世晴")
        XCTAssertNil(displayName.volume)
    }

    func testParsing_LeadingBracketWithTrailingVolume_StillUsesLeadingAuthor() {
        // Archive names end with 第〇〇巻 (never "]"), so the leading-bracket
        // fallback must still handle the archive convention.
        let displayName = MangaDisplayName(parsing: "[吾峠呼世晴]鬼滅の刃 第03巻")

        XCTAssertEqual(displayName.title, "鬼滅の刃")
        XCTAssertEqual(displayName.author, "吾峠呼世晴")
        XCTAssertEqual(displayName.volume, "第03巻")
    }

    // MARK: - Archive format: [作者名]作品名 第〇〇巻

    func testParsing_ArchiveFormat_ExtractsAuthorTitleAndVolume() {
        let displayName = MangaDisplayName(parsing: "[尾田栄一郎]ワンピース 第01巻")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
        XCTAssertEqual(displayName.volume, "第01巻")
    }

    func testParsing_ArchiveFormat_FullWidthDigitsVolume() {
        let displayName = MangaDisplayName(parsing: "[尾田栄一郎]ワンピース 第０１巻")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
        XCTAssertEqual(displayName.volume, "第０１巻")
    }

    func testParsing_ArchiveFormat_MultiDigitVolume() {
        let displayName = MangaDisplayName(parsing: "[尾田栄一郎]ワンピース 第100巻")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
        XCTAssertEqual(displayName.volume, "第100巻")
    }

    func testParsing_ArchiveFormat_WithoutSpaceBeforeVolume() {
        let displayName = MangaDisplayName(parsing: "[尾田栄一郎]ワンピース第01巻")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
        XCTAssertEqual(displayName.volume, "第01巻")
    }

    // MARK: - No brackets at all

    func testParsing_NoBrackets_KeepsEntireStringAsTitle() {
        let displayName = MangaDisplayName(parsing: "ワンピース")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertNil(displayName.author)
        XCTAssertNil(displayName.volume)
    }

    func testParsing_NoBracketsButHasVolume_ExtractsTitleAndVolume() {
        let displayName = MangaDisplayName(parsing: "ワンピース 第01巻")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertNil(displayName.author)
        XCTAssertEqual(displayName.volume, "第01巻")
    }

    // MARK: - Bracket-only / empty-title edge cases

    func testParsing_BracketOnly_DoesNotExtractAuthor() {
        // Extracting author would leave an empty title, so the whole string
        // should remain as the title instead.
        let displayName = MangaDisplayName(parsing: "[作者名]")

        XCTAssertEqual(displayName.title, "[作者名]")
        XCTAssertNil(displayName.author)
        XCTAssertNil(displayName.volume)
    }

    func testParsing_VolumeOnly_DoesNotExtractVolume() {
        // Extracting the volume would leave an empty title, so the whole
        // string should remain as the title instead.
        let displayName = MangaDisplayName(parsing: "第01巻")

        XCTAssertEqual(displayName.title, "第01巻")
        XCTAssertNil(displayName.volume)
        XCTAssertNil(displayName.author)
    }

    func testParsing_EmptyString_ResultsInEmptyTitle() {
        let displayName = MangaDisplayName(parsing: "")

        XCTAssertEqual(displayName.title, "")
        XCTAssertNil(displayName.author)
        XCTAssertNil(displayName.volume)
    }

    func testParsing_BracketsWithVolumeOnlyAfterAuthorRemoved_DoesNotExtractVolume() {
        // After removing the author brackets, the remaining title is only
        // the volume marker; volume extraction must be skipped to avoid an
        // empty title.
        let displayName = MangaDisplayName(parsing: "[作者名]第01巻")

        XCTAssertEqual(displayName.title, "第01巻")
        XCTAssertEqual(displayName.author, "作者名")
        XCTAssertNil(displayName.volume)
    }

    // MARK: - Whitespace trimming

    func testParsing_TrimsSurroundingWhitespace() {
        let displayName = MangaDisplayName(parsing: "  ワンピース[尾田栄一郎]  ")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
    }

    func testParsing_TrimsWhitespaceInsideBrackets() {
        let displayName = MangaDisplayName(parsing: "ワンピース[ 尾田栄一郎 ]")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
    }

    func testParsing_TrimsWhitespaceBetweenTitleAndVolume() {
        let displayName = MangaDisplayName(parsing: "[尾田栄一郎]ワンピース   第01巻")

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.volume, "第01巻")
    }

    // MARK: - Subtitle composition

    func testSubtitle_WithVolumeAndAuthor_JoinsBothWithMiddleDot() {
        let displayName = MangaDisplayName(parsing: "[尾田栄一郎]ワンピース 第01巻")

        XCTAssertEqual(displayName.subtitle, "第01巻 · 尾田栄一郎")
    }

    func testSubtitle_WithAuthorOnly_ReturnsAuthorOnly() {
        let displayName = MangaDisplayName(parsing: "ワンピース[尾田栄一郎]")

        XCTAssertEqual(displayName.subtitle, "尾田栄一郎")
    }

    func testSubtitle_WithVolumeOnly_ReturnsVolumeOnly() {
        let displayName = MangaDisplayName(parsing: "ワンピース 第01巻")

        XCTAssertEqual(displayName.subtitle, "第01巻")
    }

    func testSubtitle_WithNeitherVolumeNorAuthor_IsNil() {
        let displayName = MangaDisplayName(parsing: "ワンピース")

        XCTAssertNil(displayName.subtitle)
    }

    // MARK: - DriveItem.displayName extension stripping

    func testDriveItemDisplayName_ArchiveStripsExtension() {
        let item = DriveItem(
            id: "file-1",
            name: "[尾田栄一郎]ワンピース 第01巻.zip",
            mimeType: "application/zip",
            size: 1_000,
            thumbnailURL: nil,
            parentId: nil,
            createdTime: nil,
            modifiedTime: nil,
            width: nil,
            height: nil
        )

        let displayName = item.displayName

        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
        XCTAssertEqual(displayName.volume, "第01巻")
    }

    func testDriveItemDisplayName_FolderKeepsRawNameUnstripped() {
        let item = DriveItem(
            id: "folder-1",
            name: "ワンピース[尾田栄一郎]",
            mimeType: "application/vnd.google-apps.folder",
            size: nil,
            thumbnailURL: nil,
            parentId: nil,
            createdTime: nil,
            modifiedTime: nil,
            width: nil,
            height: nil
        )

        let displayName = item.displayName

        // Folders have no path extension to strip; parsing should still work
        // on the raw name.
        XCTAssertEqual(displayName.title, "ワンピース")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
    }

    func testDriveItemDisplayName_FolderWithDotInNameIsNotTreatedAsExtension() {
        // A folder literally named with a trailing ".zip"-looking suffix
        // should NOT have it stripped, since isArchive is false for folders.
        let item = DriveItem(
            id: "folder-2",
            name: "ワンピース.zip[尾田栄一郎]",
            mimeType: "application/vnd.google-apps.folder",
            size: nil,
            thumbnailURL: nil,
            parentId: nil,
            createdTime: nil,
            modifiedTime: nil,
            width: nil,
            height: nil
        )

        let displayName = item.displayName

        XCTAssertEqual(displayName.title, "ワンピース.zip")
        XCTAssertEqual(displayName.author, "尾田栄一郎")
    }
}
