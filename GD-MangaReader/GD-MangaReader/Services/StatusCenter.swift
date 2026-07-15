// StatusCenter.swift
// GD-MangaReader
//
// アプリ全体のフィードバック（トースト・ハプティクス）を一元管理する統合レイヤー。
// アプリルートから Environment 経由で注入され、各画面はこれを通じてトーストを表示する。
// 表示自体はルートの .statusCenterOverlay() が担う（StatusCenterOverlay.swift 参照）。

import SwiftUI
import UIKit

/// アプリ全体のステータスフィードバックを一元管理するクラス。
///
/// 設計上の制約（意図的に最小限に保つ）:
/// - トーストは常に1枚（新しいトーストは表示中のものを置き換える。キューやスタックは持たない）
/// - アクションボタンは最大1つ（`ToastData.action`）
/// - 例外として、アクション付きトースト（「元に戻す」等）の表示中に来たアクション無し
///   トーストだけは退避スロット（`pendingToast`、最新1件のみ）に逃がし、アクション付き
///   トーストの終了後に表示する。汎用のキュー/優先度システムは意図的に作らない
@MainActor
@Observable
final class StatusCenter {
    /// アプリ全体で共有する唯一のインスタンス（アプリルートで Environment に注入する）
    static let shared = StatusCenter()

    /// 現在表示中のトースト（表示はルートオーバーレイが担当する）
    private(set) var currentToast: ToastData?

    /// アクション付きトーストの表示中に到着した、アクション無しトーストの退避先（最新1件のみ）。
    /// 「元に戻す」のUndo猶予（トースト表示時間）を後続の情報トーストに潰されないようにするため、
    /// 置き換えずにここへ退避し、アクション付きトーストの終了時（自動消去・タップ・アクション実行の
    /// いずれの経路でも）に新しいタイマーで表示する
    @ObservationIgnored
    private var pendingToast: ToastData?

    /// ダウンロードキュー一覧シートの表示状態。
    /// ルートオーバーレイが唯一のsheetをこれにバインドし、
    /// バナータップ・ツールバーメニューのどちらも showDownloadQueue() 経由で開く
    var isDownloadQueuePresented = false

    /// 自動消去タスク（新しいトーストが来たらキャンセルして張り直す）
    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    /// トーストの自動消去までの時間（テストから短縮できるよう注入可能にする）
    let dismissInterval: Duration

    /// 事前にprepare()して遅延を抑えるための通知ハプティクスジェネレータ
    private static let feedbackGenerator = UINotificationFeedbackGenerator()

    init(dismissInterval: Duration = .seconds(3)) {
        self.dismissInterval = dismissInterval
    }

    /// トーストを表示する。
    /// 表示中のトーストがあれば即座に置き換え、3秒後に自動で消える（タップでも消せる）。
    /// success / error タイプの場合は自動でハプティクスも鳴らす。
    ///
    /// 退避ポリシー（最小限に留める）:
    /// - 表示中がアクション付きで、来たものがアクション無し → 置き換えず`pendingToast`に退避
    ///   （複数来た場合は最新のみ保持）。アクション付きトーストの終了時に自動で表示される
    /// - 来たものもアクション付き → 即座に置き換える。「最新のUndoが勝つ」スナックバー標準の
    ///   セマンティクスであり、古いアクションの機会が失われるのは意図的（多段Undoスタックは作らない）
    /// - それ以外（アクション無し同士、アクション付きがアクション無しを上書き）は従来通り置き換える
    func show(_ toast: ToastData) {
        if currentToast?.action != nil && toast.action == nil {
            pendingToast = toast
            return
        }
        display(toast)
    }

    /// トーストを実際に表示スロットへ載せ、ハプティクスと自動消去タイマーを張る
    private func display(_ toast: ToastData) {
        dismissTask?.cancel()

        withAnimation {
            currentToast = toast
        }

        // VoiceOver利用時はトーストの内容を読み上げる
        // （トーストは3秒で自動消去されるため、フォーカス移動なしで内容を伝える）
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(toast.title)、\(toast.message)"
        )

        switch toast.type {
        case .success:
            Self.haptic(.success)
        case .error:
            Self.haptic(.error)
        case .info, .warning:
            break
        }

        dismissTask = Task { [weak self, dismissInterval] in
            try? await Task.sleep(for: dismissInterval)
            guard !Task.isCancelled else { return }
            self?.dismissToast()
        }
    }

    /// 表示中のトーストを閉じる（自動消去・タップ・アクション実行のすべての経路で呼ばれる）。
    /// 退避中のトーストがあればここで昇格させ、新しいタイマーで表示する。
    ///
    /// アクションタップ時の優先順位: ToastViewは「dismiss → ハンドラー実行」の順で呼ぶため、
    /// ここで昇格した退避トーストは、ハンドラーが後続トースト（例: 「N件キャンセルしました」）を
    /// 表示すると即座に置き換えられる。ハンドラー発のトーストが表示スロットを勝ち取り、
    /// 退避トーストはその場合破棄される（アクション実行結果の報告を優先する意図的な仕様）
    func dismissToast() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation {
            currentToast = nil
        }

        if let pending = pendingToast {
            pendingToast = nil
            display(pending)
        }
    }

    /// ダウンロードキュー一覧シートを表示する
    func showDownloadQueue() {
        isDownloadQueuePresented = true
    }

    /// 通知ハプティクスを鳴らす共通入口。
    /// 後続ステップ（リーダー表示中のフィードバック等）はここからハプティクスを発火する。
    static func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(type)
    }
}
