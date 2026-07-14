// DownloadQueueView.swift
// GD-MangaReader
//
// バックグラウンドダウンロードキューの一覧表示

import SwiftUI

/// ダウンロードキューの一覧を表示するシート
struct DownloadQueueView: View {
    @Environment(\.dismiss) private var dismiss

    private var manager: DownloadQueueManager { .shared }

    var body: some View {
        NavigationStack {
            Group {
                if manager.tasks.isEmpty {
                    ContentUnavailableView(
                        "ダウンロードはありません",
                        systemImage: "arrow.down.circle",
                        description: Text("ファイルやシリーズをダウンロードすると\nここに表示されます")
                    )
                } else {
                    List {
                        ForEach(manager.tasks) { task in
                            DownloadQueueRow(task: task) {
                                manager.cancel(task)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("ダウンロード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                if !manager.tasks.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                manager.clearFinished()
                            } label: {
                                Label("終了済みをクリア", systemImage: "trash")
                            }
                            .disabled(manager.finishedCount == 0)

                            Button(role: .destructive) {
                                manager.cancelAll()
                            } label: {
                                Label("すべてキャンセル", systemImage: "xmark.circle")
                            }
                            .disabled(!manager.isActive)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

/// キュー内の1タスクを表示する行
struct DownloadQueueRow: View {
    let task: DownloadQueueTask
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 状態アイコン
            statusIcon
                .frame(width: 32)

            // 名前と進捗
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.subheadline)
                    .lineLimit(1)

                statusDetail
            }

            Spacer()

            // キャンセルボタン
            if !task.state.isFinished {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.state {
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .running:
            ProgressView()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.appSuccess)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.appDestructive)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch task.state {
        case .queued:
            Text("待機中")
                .font(.caption)
                .foregroundColor(.secondary)

        case .running:
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .tint(.appProgressTint)

                Text(runningStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

        case .completed:
            Text("完了")
                .font(.caption)
                .foregroundColor(.appSuccess)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.appDestructive)
                .lineLimit(2)

        case .cancelled:
            Text("キャンセル済み")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var runningStatusText: String {
        guard let downloader = task.downloader else { return "処理中..." }
        switch downloader.status {
        case .extracting:
            return "解凍中... \(Int(downloader.extractProgress * 100))%"
        default:
            return "ダウンロード中... \(Int(downloader.downloadProgress * 100))%"
        }
    }
}

#Preview {
    DownloadQueueView()
}
