import XCTest
@testable import GD_MangaReader

/// `DriveService.escapeDriveQueryValue(_:)`は、Google Driveの`q`クエリの
/// シングルクォート文字列リテラルへユーザー入力を安全に埋め込むための
/// エスケープを行う純粋関数。バックスラッシュを先に処理してから
/// シングルクォートを処理する必要がある（順序を誤ると二重エスケープになる）。
@MainActor
final class DriveQueryEscapingTests: XCTestCase {

    func testEscape_PlainText_PassesThroughUnchanged() {
        XCTAssertEqual(DriveService.escapeDriveQueryValue("hello world"), "hello world")
    }

    func testEscape_SingleQuote_IsEscapedWithBackslash() {
        XCTAssertEqual(DriveService.escapeDriveQueryValue("it's"), "it\\'s")
    }

    func testEscape_Backslash_IsDoubled() {
        XCTAssertEqual(DriveService.escapeDriveQueryValue("a\\b"), "a\\\\b")
    }

    func testEscape_BackslashThenQuote_BackslashIsDoubledBeforeQuoteEscaping() {
        // Input already contains `\'` (backslash followed by single quote).
        // Backslash must be escaped FIRST (-> `\\'`), and only then is the
        // single quote escaped (-> `\\\'`). If the order were reversed, the
        // quote's escaping backslash would itself get doubled, producing an
        // incorrect result.
        XCTAssertEqual(DriveService.escapeDriveQueryValue("\\'"), "\\\\\\'")
    }

    func testEscape_EmptyString_ReturnsEmptyString() {
        XCTAssertEqual(DriveService.escapeDriveQueryValue(""), "")
    }

    func testEscape_JapaneseText_PassesThroughUnchanged() {
        XCTAssertEqual(DriveService.escapeDriveQueryValue("鬼滅の刃"), "鬼滅の刃")
    }

    func testEscape_MultipleQuotesAndBackslashesMixed() {
        // "O'Brien\Test's" -> backslashes doubled, then quotes escaped.
        XCTAssertEqual(
            DriveService.escapeDriveQueryValue("O'Brien\\Test's"),
            "O\\'Brien\\\\Test\\'s"
        )
    }
}
