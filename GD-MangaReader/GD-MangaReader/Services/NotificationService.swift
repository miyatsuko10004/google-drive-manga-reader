// NotificationService.swift
// GD-MangaReader
//
// ダウンロード完了のローカル通知を管理するサービス。
// フォアグラウンドでは既存のトースト（StatusCenter経由）がフィードバックを担うため、
// 通知はアプリが非アクティブなときだけ発行する（二重フィードバックの防止）。

import Foundation
import UIKit
import UserNotifications

// MARK: - Download Feedback Policy

/// ダウンロード完了フィードバックの判定ロジック（純粋関数、ユニットテスト対象）。
/// 文言は LibraryView のトーストと揃える（片方だけ変えないこと）。
enum DownloadFeedbackPolicy {
    /// ローカル通知を発行すべきかどうか。
    /// - フォアグラウンド（active）ではトーストが表示されるため通知は出さない
    /// - 完了・失敗が1件もない（全キャンセル等）場合も出さない
    static func shouldPostNotification(completed: Int, failed: Int, isAppActive: Bool) -> Bool {
        guard completed + failed > 0 else { return false }
        return !isAppActive
    }

    /// 通知タイトル（トーストのタイトルと同一文言）
    static func notificationTitle(completed: Int, failed: Int) -> String {
        if failed == 0 {
            return "ダウンロード完了"
        } else {
            return "ダウンロード完了 (\(failed)件失敗)"
        }
    }

    /// 通知本文（トーストのメッセージと同一文言）
    static func notificationBody(completed: Int, failed: Int) -> String {
        if failed == 0 {
            return "\(completed)件のダウンロードが完了しました"
        } else {
            return "\(completed)件完了、\(failed)件失敗しました"
        }
    }
}

// MARK: - Notification Service

/// UNUserNotificationCenter の薄いラッパー。
///
/// 設計方針:
/// - 許可リクエストは「初めてダウンロードをキューに入れたとき」に遅延実行する
///   （一度もダウンロードしないユーザーには許可ダイアログを出さない）
/// - 許可が拒否されている場合はすべて黙って何もしない（エラーも再プロンプトもなし）
/// - 通知はキューが空になったタイミングで1件だけ発行する（ファイルごとには出さない）
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// 起動ごとに許可状態の確認・リクエストを1回に抑えるフラグ
    private var hasHandledAuthorizationThisLaunch = false

    private override init() {
        super.init()
        // applicationStateが .inactive（コントロールセンター表示中・許可ダイアログ表示中・
        // 着信中など）のときに発行した通知は、フォアグラウンド扱いのため delegate の
        // willPresent がないとバナー表示されず通知センターに黙って積まれてしまう。
        // それを防ぐため willPresent で [.banner, .sound] を返す delegate を設定する。
        //
        // delegate は本来アプリ起動の早い段階で設定すべきだが、通知を発行するのは
        // このサービス自身だけであり、発行前に必ず shared（= この init）が触られるため、
        // 初回利用時の遅延設定で問題ない（起動時に不要な初期化をしないための意図的な選択）。
        UNUserNotificationCenter.current().delegate = self
    }

    /// アプリがフォアグラウンド（.active / .inactive）にいる間に通知が配信された場合の表示方法。
    /// .active 時はそもそも通知を発行しない（postDownloadCompletionのガード）ため、
    /// ここが効くのは実質 .inactive のときのみ。バナーとして見えるようにする
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 通知許可が未決定（notDetermined）の場合のみシステムの許可ダイアログを表示する。
    /// 拒否済み・許可済みの場合は何もしない。1起動につき1回しか確認しない。
    func requestAuthorizationIfNeeded() async {
        guard !hasHandledAuthorizationThisLaunch else { return }
        hasHandledAuthorizationThisLaunch = true

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        // 拒否されてもエラーにしない（以後は authorizationStatus のチェックで自然にスキップされる）
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// ダウンロードキューが空になったときの完了通知を発行する。
    /// アプリがフォアグラウンド（active）の場合はトーストが担当するため何もしない。
    /// 通知許可がない場合も黙ってスキップする。
    func postDownloadCompletion(completed: Int, failed: Int) async {
        let isAppActive = UIApplication.shared.applicationState == .active
        guard DownloadFeedbackPolicy.shouldPostNotification(
            completed: completed,
            failed: failed,
            isAppActive: isAppActive
        ) else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = DownloadFeedbackPolicy.notificationTitle(completed: completed, failed: failed)
        content.body = DownloadFeedbackPolicy.notificationBody(completed: completed, failed: failed)
        content.sound = .default

        // trigger: nil = 即時配信。タップ時はアプリを開くだけ（ディープリンクはスコープ外）
        let request = UNNotificationRequest(
            identifier: "download-completion-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
