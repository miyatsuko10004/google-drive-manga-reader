import XCTest
@testable import GD_MangaReader

@MainActor
final class StatusCenterTests: XCTestCase {

    private func makeToast(title: String = "Title", message: String = "Message", type: ToastData.ToastType = .info) -> ToastData {
        ToastData(title: title, message: message, type: type)
    }

    func testShow_SetsCurrentToast() {
        // Arrange
        let center = StatusCenter(dismissInterval: .seconds(3))
        let toast = makeToast(title: "Hello", message: "World", type: .success)

        // Act
        center.show(toast)

        // Assert
        XCTAssertNotNil(center.currentToast)
        XCTAssertEqual(center.currentToast?.title, "Hello")
        XCTAssertEqual(center.currentToast?.message, "World")
    }

    func testShow_AutoDismissesAfterInterval() async throws {
        // Arrange
        let center = StatusCenter(dismissInterval: .milliseconds(50))

        // Act
        center.show(makeToast())
        XCTAssertNotNil(center.currentToast)

        // Assert: poll until dismissed or timeout, generous window for CI
        let deadline = Date().addingTimeInterval(2.0)
        while center.currentToast != nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(center.currentToast, "Toast should auto-dismiss after dismissInterval elapses")
    }

    func testShow_ReplacingToast_ReArmsDismissTimer() async throws {
        // Arrange: base interval long enough to avoid flakiness in CI
        let interval: Duration = .milliseconds(200)
        let center = StatusCenter(dismissInterval: interval)

        // Act: show A, wait ~half the interval, then show B (which should re-arm the timer)
        center.show(makeToast(title: "A"))
        try await Task.sleep(for: .milliseconds(100))
        center.show(makeToast(title: "B"))

        // Assert: after another ~0.7x interval from B's show, A's stale dismiss task
        // must not have cleared B's toast.
        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(center.currentToast?.title, "B", "B's toast must still be visible; A's stale auto-dismiss task must not clear it")

        // Assert: after the full interval has elapsed since B was shown, it should clear.
        let deadline = Date().addingTimeInterval(2.0)
        while center.currentToast != nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(center.currentToast, "B's toast should auto-dismiss once its own interval elapses")
    }

    func testDismissToast_ClearsImmediatelyAndPreventsLateResurrection() async throws {
        // Arrange
        let interval: Duration = .milliseconds(80)
        let center = StatusCenter(dismissInterval: interval)

        // Act
        center.show(makeToast())
        XCTAssertNotNil(center.currentToast)
        center.dismissToast()

        // Assert: cleared immediately
        XCTAssertNil(center.currentToast)

        // Wait past the original auto-dismiss interval; nothing should resurrect
        // or double-clear (no crash, still nil).
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(center.currentToast, "Toast should remain nil; the cancelled auto-dismiss task must not resurrect or double-clear state")
    }

    // MARK: - Action toast eviction policy

    private func makeActionToast(
        title: String = "Undo",
        handler: @escaping () -> Void = {}
    ) -> ToastData {
        ToastData(
            title: title,
            message: "Message",
            type: .info,
            action: ToastAction(label: "元に戻す", handler: handler)
        )
    }

    /// currentToastが指定タイトルになるまでポーリングする（CI向けに余裕を持たせる）
    private func waitForToast(
        _ center: StatusCenter,
        title: String?,
        timeout: TimeInterval = 2.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while center.currentToast?.title != title && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testShow_InfoWhileActionToastVisible_IsParkedAndShownAfterActionToastExpires() async throws {
        // Arrange
        let center = StatusCenter(dismissInterval: .milliseconds(80))
        center.show(makeActionToast(title: "Undo"))

        // Act: アクション付きトーストの表示中にアクション無しトーストを表示する
        center.show(makeToast(title: "Parked"))

        // Assert: アクション付きトーストは潰されず表示されたまま
        XCTAssertEqual(center.currentToast?.title, "Undo", "Action toast must not be evicted by an actionless toast")

        // Assert: アクション付きトーストの自動消去後、退避されたトーストが表示される
        try await waitForToast(center, title: "Parked")
        XCTAssertEqual(center.currentToast?.title, "Parked", "Parked toast should be promoted after the action toast expires")

        // Assert: 退避トーストにも新しいタイマーが張られ、自動消去される
        try await waitForToast(center, title: nil)
        XCTAssertNil(center.currentToast, "Promoted toast should auto-dismiss on its own fresh timer")
    }

    func testShow_ActionToastWhileActionToastVisible_ReplacesImmediately() {
        // Arrange
        let center = StatusCenter(dismissInterval: .seconds(3))
        center.show(makeActionToast(title: "UndoA"))

        // Act: 新しいアクション付きトーストは即座に置き換える（最新のUndoが勝つ）
        center.show(makeActionToast(title: "UndoB"))

        // Assert
        XCTAssertEqual(center.currentToast?.title, "UndoB", "A newer action toast must replace the current one immediately")
    }

    func testDismissToast_OnActionToast_FlushesPendingInfoToast() async throws {
        // Arrange
        let center = StatusCenter(dismissInterval: .milliseconds(80))
        center.show(makeActionToast(title: "Undo"))
        center.show(makeToast(title: "Parked"))
        XCTAssertEqual(center.currentToast?.title, "Undo")

        // Act: タップ消去（dismissToast）でも退避トーストが昇格する
        center.dismissToast()

        // Assert
        XCTAssertEqual(center.currentToast?.title, "Parked", "Manual dismiss must promote the parked toast")

        // Assert: 昇格したトーストは新しいタイマーで自動消去される
        try await waitForToast(center, title: nil)
        XCTAssertNil(center.currentToast, "Promoted toast should auto-dismiss on a fresh timer")
    }

    func testActionTap_HandlerIssuedToast_WinsOverParkedToast() {
        // Arrange: 「元に戻す」実行時に結果報告トーストを出すハンドラー
        let center = StatusCenter(dismissInterval: .seconds(3))
        center.show(makeActionToast(title: "Undo", handler: {
            center.show(ToastData(title: "FollowUp", message: "3件キャンセルしました", type: .info))
        }))
        center.show(makeToast(title: "Parked"))
        XCTAssertEqual(center.currentToast?.title, "Undo")

        // Act: ToastViewのアクションボタンと同じ順序（dismiss → ハンドラー実行）を再現する
        let action = center.currentToast?.action
        XCTAssertNotNil(action)
        center.dismissToast()
        action?.handler()

        // Assert: ハンドラー発のトーストが表示スロットを勝ち取る。
        // 退避トーストはdismiss時に一瞬昇格するが、直後にハンドラー発トーストへ
        // 置き換えられて破棄される（アクション実行結果の報告を優先する仕様）
        XCTAssertEqual(center.currentToast?.title, "FollowUp", "Handler-issued toast must win the visible slot over the parked toast")
    }

    func testShowDownloadQueue_SetsIsDownloadQueuePresented() {
        // Arrange
        let center = StatusCenter()
        XCTAssertFalse(center.isDownloadQueuePresented)

        // Act
        center.showDownloadQueue()

        // Assert
        XCTAssertTrue(center.isDownloadQueuePresented)
    }
}
