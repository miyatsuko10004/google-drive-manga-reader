// DownloadFeedbackPolicyTests.swift
// GD-MangaReaderTests
//
// ダウンロード完了フィードバックの判定ロジック（純粋関数）のテスト。
// 実際のUNUserNotificationCenterへの通知発行やハプティクスはユニットテストでは検証できないため、
// 「いつ通知を出すか」「どの文言を出すか」の判定部分のみを対象とする。

import XCTest
@testable import GD_MangaReader

final class DownloadFeedbackPolicyTests: XCTestCase {

    // MARK: - shouldPostNotification

    func testShouldPostNotification_BackgroundWithCompletions_ReturnsTrue() {
        XCTAssertTrue(DownloadFeedbackPolicy.shouldPostNotification(completed: 3, failed: 0, isAppActive: false))
    }

    func testShouldPostNotification_BackgroundWithFailuresOnly_ReturnsTrue() {
        XCTAssertTrue(DownloadFeedbackPolicy.shouldPostNotification(completed: 0, failed: 2, isAppActive: false))
    }

    func testShouldPostNotification_BackgroundWithMixedResults_ReturnsTrue() {
        XCTAssertTrue(DownloadFeedbackPolicy.shouldPostNotification(completed: 5, failed: 1, isAppActive: false))
    }

    func testShouldPostNotification_ForegroundActive_ReturnsFalse() {
        // フォアグラウンドではトースト＋ハプティクスが担当するため、通知は出さない
        XCTAssertFalse(DownloadFeedbackPolicy.shouldPostNotification(completed: 3, failed: 1, isAppActive: true))
    }

    func testShouldPostNotification_NoResults_ReturnsFalse() {
        // 全件キャンセル等で完了も失敗も0件の場合は何も出さない
        XCTAssertFalse(DownloadFeedbackPolicy.shouldPostNotification(completed: 0, failed: 0, isAppActive: false))
        XCTAssertFalse(DownloadFeedbackPolicy.shouldPostNotification(completed: 0, failed: 0, isAppActive: true))
    }

    // MARK: - notificationTitle（トーストのタイトルと同一文言）

    func testNotificationTitle_AllSucceeded() {
        XCTAssertEqual(
            DownloadFeedbackPolicy.notificationTitle(completed: 3, failed: 0),
            "ダウンロード完了"
        )
    }

    func testNotificationTitle_WithFailures_IncludesFailedCount() {
        XCTAssertEqual(
            DownloadFeedbackPolicy.notificationTitle(completed: 3, failed: 2),
            "ダウンロード完了 (2件失敗)"
        )
    }

    func testNotificationTitle_AllFailed_IncludesFailedCount() {
        XCTAssertEqual(
            DownloadFeedbackPolicy.notificationTitle(completed: 0, failed: 2),
            "ダウンロード完了 (2件失敗)"
        )
    }

    // MARK: - notificationBody（トーストのメッセージと同一文言）

    func testNotificationBody_AllSucceeded() {
        XCTAssertEqual(
            DownloadFeedbackPolicy.notificationBody(completed: 3, failed: 0),
            "3件のダウンロードが完了しました"
        )
    }

    func testNotificationBody_WithFailures_IncludesBothCounts() {
        XCTAssertEqual(
            DownloadFeedbackPolicy.notificationBody(completed: 3, failed: 2),
            "3件完了、2件失敗しました"
        )
    }

    func testNotificationBody_AllFailed_IncludesBothCounts() {
        XCTAssertEqual(
            DownloadFeedbackPolicy.notificationBody(completed: 0, failed: 2),
            "0件完了、2件失敗しました"
        )
    }
}
