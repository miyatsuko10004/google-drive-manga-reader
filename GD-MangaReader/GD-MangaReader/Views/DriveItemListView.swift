import SwiftUI

struct DriveItemListView: View {
    let libraryViewModel: LibraryViewModel
    let onItemTap: (DriveItem) -> Void
    let onBulkDownload: (DriveItem) -> Void
    let onDownloadSingle: (DriveItem) -> Void
    let onDownloadFrom: (DriveItem) -> Void

    private var downloadQueue: DownloadQueueManager { .shared }

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(libraryViewModel.displayItems) { item in
                // onTapGestureではなくButtonで包み、押下中の視覚フィードバックを付ける
                Button {
                    onItemTap(item)
                } label: {
                    DriveItemListRow(
                        item: item,
                        isBulkDownloading: item.isFolder
                            ? downloadQueue.hasPendingTasks(inFolder: item.id)
                            : downloadQueue.isInQueue(driveFileId: item.id),
                        localComic: libraryViewModel.downloadedComics[item.id],
                        seriesThumbnailURL: libraryViewModel.seriesThumbnails[item.id] ?? nil
                    )
                }
                .buttonStyle(PressableCellButtonStyle())
                .task {
                    if item.isFolder {
                        await libraryViewModel.resolveSeriesThumbnail(for: item)
                    }
                }
                .driveItemContextMenu(
                    for: item,
                    isDownloaded: libraryViewModel.downloadedComics[item.id] != nil,
                    isQueued: downloadQueue.isInQueue(driveFileId: item.id),
                    isOfflineMode: libraryViewModel.isOfflineMode,
                    onBulkDownload: onBulkDownload,
                    onDownloadSingle: onDownloadSingle,
                    onDownloadFrom: onDownloadFrom
                )
            }
        }
    }
}

// MARK: - Button Style

/// グリッドセル・リスト行の押下フィードバック用ボタンスタイル。
/// 押している間だけわずかに縮小＋減光し、タップ可能であることを視覚的に伝える。
/// カスタムButtonStyleのためラベルの文字色はティントに置き換わらず元のまま表示される
struct PressableCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Context Menu

/// フォルダ/アーカイブ用の長押しコンテキストメニュー
struct DriveItemContextMenuModifier: ViewModifier {
    let item: DriveItem
    let isDownloaded: Bool
    let isQueued: Bool
    let isOfflineMode: Bool
    let onBulkDownload: (DriveItem) -> Void
    let onDownloadSingle: (DriveItem) -> Void
    let onDownloadFrom: (DriveItem) -> Void

    func body(content: Content) -> some View {
        // オフライン中はダウンロード操作自体を提示しない
        if isOfflineMode {
            content
        } else if item.isFolder {
            content.contextMenu {
                Button {
                    onBulkDownload(item)
                } label: {
                    Label("シリーズ一括ダウンロード", systemImage: "square.and.arrow.down.on.square")
                }
            }
        } else if item.isArchive {
            content.contextMenu {
                // ダウンロード済み・キュー投入済みの場合は「この巻をダウンロード」を出さない
                if !isDownloaded && !isQueued {
                    Button {
                        onDownloadSingle(item)
                    } label: {
                        Label("この巻をダウンロード", systemImage: "arrow.down.circle")
                    }
                }

                Button {
                    onDownloadFrom(item)
                } label: {
                    Label("この巻以降をダウンロード", systemImage: "square.and.arrow.down.on.square")
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func driveItemContextMenu(
        for item: DriveItem,
        isDownloaded: Bool,
        isQueued: Bool,
        isOfflineMode: Bool,
        onBulkDownload: @escaping (DriveItem) -> Void,
        onDownloadSingle: @escaping (DriveItem) -> Void,
        onDownloadFrom: @escaping (DriveItem) -> Void
    ) -> some View {
        modifier(DriveItemContextMenuModifier(
            item: item,
            isDownloaded: isDownloaded,
            isQueued: isQueued,
            isOfflineMode: isOfflineMode,
            onBulkDownload: onBulkDownload,
            onDownloadSingle: onDownloadSingle,
            onDownloadFrom: onDownloadFrom
        ))
    }
}
