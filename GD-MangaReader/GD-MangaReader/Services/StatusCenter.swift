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
@MainActor
@Observable
final class StatusCenter {
    /// アプリ全体で共有する唯一のインスタンス（アプリルートで Environment に注入する）
    static let shared = StatusCenter()

    /// 現在表示中のトースト（表示はルートオーバーレイが担当する）
    private(set) var currentToast: ToastData?

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
    func show(_ toast: ToastData) {
        dismissTask?.cancel()

        withAnimation {
            currentToast = toast
        }

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

    /// 表示中のトーストを閉じる（タップ・アクション実行時にも呼ばれる）
    func dismissToast() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation {
            currentToast = nil
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
