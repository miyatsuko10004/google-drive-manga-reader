// DownloadSheet.swift
// GD-MangaReader
//
// ダウンロード進捗表示シート
// ダウンロードはDownloadQueueManagerで実行されるため、シートを閉じてもバックグラウンドで継続する

import SwiftUI

/// ダウンロード対象
enum DownloadTarget {
    case file(DriveItem)
    case folder(id: String, name: String)

    var name: String {
        switch self {
        case .file(let item): return item.name
        case .folder(_, let name): return name
        }
    }

    var iconName: String {
        switch self {
        case .file(let item): return item.iconName
        case .folder: return "folder.fill"
        }
    }

    var sizeText: String {
        switch self {
        case .file(let item): return item.formattedSize
        case .folder: return "フォルダ内の全画像"
        }
    }
}

/// ダウンロード進捗を表示するシート
struct DownloadSheet: View {
    let target: DownloadTarget
    @Binding var isPresented: Bool
    var onComplete: (LocalComic) -> Void

    @Environment(AuthViewModel.self) private var authViewModel
    @State private var queueTask: DownloadQueueTask?
    @State private var downloadedComic: LocalComic?

    private var queueManager: DownloadQueueManager { .shared }

    /// 表示すべき完了コミック
    private var completedComic: LocalComic? {
        downloadedComic ?? queueTask?.comic
    }

    /// タスクが待機中または実行中か
    private var isProcessing: Bool {
        if let state = queueTask?.state {
            return !state.isFinished
        }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // ファイルアイコン
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: target.iconName)
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                }

                // ファイル名
                Text(target.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // サイズ
                Text(target.sizeText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // 進捗表示
                progressView

                Spacer()

                // ボタン
                actionButtons
            }
            .padding()
            .navigationTitle("ダウンロード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // ダウンロードはバックグラウンドで継続するため、いつでも閉じられる
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
            .task {
                // ダウンロード済み・実行中タスクのチェック
                checkExistingState()
            }
        }
    }

    // MARK: - Progress View

    @ViewBuilder
    private var progressView: some View {
        VStack(spacing: 16) {
            if completedComic != nil {
                completedView
            } else {
                switch queueTask?.state {
                case nil:
                    Text("ダウンロードの準備ができました")
                        .foregroundColor(.secondary)

                case .queued:
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("ダウンロード待機中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .running:
                    runningView

                case .completed:
                    completedView

                case .failed(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)

                        Text("エラーが発生しました")
                            .font(.headline)
                            .foregroundColor(.red)

                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .cancelled:
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)

                        Text("キャンセルされました")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    /// 実行中の進捗表示
    @ViewBuilder
    private var runningView: some View {
        if let downloader = queueTask?.downloader {
            switch downloader.status {
            case .extracting:
                VStack(spacing: 8) {
                    ProgressView(value: downloader.extractProgress)
                        .progressViewStyle(.linear)
                        .tint(.green)

                    Text("解凍中... \(Int(downloader.extractProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            default:
                VStack(spacing: 8) {
                    ProgressView(value: downloader.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    Text(downloadStatusText(downloader: downloader))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else {
            ProgressView()
        }
    }

    /// 完了表示
    private var completedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("完了しました！")
                .font(.headline)
                .foregroundColor(.green)

            if let comic = completedComic {
                Text("\(comic.pageCount)ページ")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func downloadStatusText(downloader: DownloaderViewModel) -> String {
        if case .folder = target {
            return "ダウンロード中... \(Int(downloader.downloadProgress * 100))%\n\(downloader.currentFileName ?? "")"
        } else {
            return "ダウンロード中... \(Int(downloader.downloadProgress * 100))%"
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let comic = completedComic {
                Button {
                    onComplete(comic)
                    isPresented = false
                } label: {
                    Label("読み始める", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                switch queueTask?.state {
                case nil, .cancelled:
                    Button {
                        startDownload()
                    } label: {
                        Label("ダウンロード開始", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                case .queued, .running:
                    Button {
                        isPresented = false
                    } label: {
                        Label("バックグラウンドで続行", systemImage: "arrow.down.circle.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        if let queueTask {
                            queueManager.cancel(queueTask)
                        }
                    } label: {
                        Label("ダウンロードを中止", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                case .failed:
                    Button {
                        startDownload()
                    } label: {
                        Label("再試行", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                case .completed:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Actions

    private func startDownload() {
        queueTask = queueManager.enqueue(target)
        if queueTask == nil {
            // enqueueがnilを返す＝既にダウンロード済み
            checkExistingState()
        }
    }

    /// ダウンロード済み・実行中タスクをチェックして状態を復元
    private func checkExistingState() {
        let driveFileId: String
        switch target {
        case .file(let item): driveFileId = item.id
        case .folder(let id, _): driveFileId = id
        }

        // ダウンロード済みなら完了状態で表示
        if let existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: driveFileId),
           existingComic.status == .completed {
            downloadedComic = existingComic
            return
        }

        // 既にキューにあれば（完了・失敗・キャンセル済みも含め）そのタスクの状態を表示
        if let existingTask = queueManager.lastKnownTask(forDriveFileId: driveFileId) {
            queueTask = existingTask
        }
    }
}

#Preview {
    DownloadSheet(
        target: .file(.mockZipFile),
        isPresented: .constant(true),
        onComplete: { _ in }
    )
    .environment(AuthViewModel())
}
