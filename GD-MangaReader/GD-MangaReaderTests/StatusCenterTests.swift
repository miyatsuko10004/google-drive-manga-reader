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
