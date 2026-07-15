// StatusCenterOverlay.swift
// GD-MangaReader
//
// アプリルートに1回だけ適用する統合フィードバックオーバーレイ。
// 画面下部に2つのスロットを持つ:
// - 常駐スロット: ダウンロード進捗バナー（DownloadQueueManager.shared を直接監視）
// - 一時スロット: トースト（StatusCenter.currentToast。常にバナーの上に重ならず積まれる）
//
// 既知の制限（意図的に許容）: このオーバーレイはルートビューに載るため、
// fullScreenCover（リーダー）や .sheet などの presentation の下に隠れる。
// リーダーやシート表示中に発火したトーストはその上には表示されない。
// 既存コードはトーストを出す前にリーダーを閉じるパスを維持しており、
// 表示中のフィードバックは後続ステップで通知・ハプティクスにより補完する。

import SwiftUI

/// 統合フィードバックオーバーレイ（トースト + ダウンロード進捗バナー）
private struct StatusCenterOverlayModifier: ViewModifier {
    @Environment(StatusCenter.self) private var statusCenter
    @Environment(AuthViewModel.self) private var authViewModel

    private var downloadQueue: DownloadQueueManager { .shared }

    func body(content: Content) -> some View {
        @Bindable var statusCenter = statusCenter

        return content
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    // 一時スロット: トースト（バナーの上に積む）
                    if let toast = statusCenter.currentToast {
                        ToastView(data: toast) {
                            statusCenter.dismissToast()
                        }
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // 常駐スロット: ダウンロード進捗バナー。
                    // ルートオーバーレイはログイン画面の上にも載るため、
                    // サインイン中（またはオフラインモード）のみ表示する
                    if downloadQueue.isActive
                        && (authViewModel.isSignedIn || authViewModel.isOfflineMode) {
                        DownloadQueueBannerView {
                            statusCenter.showDownloadQueue()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(), value: downloadQueue.isActive)
            }
            // キュー一覧シートの唯一のpresenter（バナータップ・ツールバーメニュー共用）
            .sheet(isPresented: $statusCenter.isDownloadQueuePresented) {
                DownloadQueueView()
            }
    }
}

extension View {
    /// 統合フィードバックオーバーレイを適用する（アプリルートで1回だけ呼ぶこと）
    func statusCenterOverlay() -> some View {
        modifier(StatusCenterOverlayModifier())
    }
}

/// ダウンロードキュー進捗バナー（タップでキュー一覧を表示）
private struct DownloadQueueBannerView: View {
    let onTap: () -> Void

    private var downloadQueue: DownloadQueueManager { .shared }

    var body: some View {
        // onTapGestureではなくButtonにすることで、VoiceOverが操作可能なボタンとして扱う
        Button(action: onTap) {
            HStack(spacing: 16) {
                ProgressView()
                    .tint(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text("バックグラウンドダウンロード中...")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    HStack {
                        ProgressView(value: downloadQueue.overallProgress)
                            .progressViewStyle(.linear)
                            .tint(.appProgressTint)

                        Text("\(downloadQueue.finishedCount) / \(downloadQueue.totalCount)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .padding()
            .shadow(radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "バックグラウンドダウンロード中、\(downloadQueue.finishedCount)件完了、全\(downloadQueue.totalCount)件"
        )
        .accessibilityHint("タップでダウンロードキューを表示")
    }
}
