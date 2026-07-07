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
            ForEach(libraryViewModel.filteredItems) { item in
                DriveItemListRow(
                    item: item,
                    isBulkDownloading: item.isFolder
                        ? downloadQueue.hasPendingTasks(inFolder: item.id)
                        : downloadQueue.isInQueue(driveFileId: item.id),
                    localComic: libraryViewModel.downloadedComics[item.id],
                    folderThumbnails: libraryViewModel.folderThumbnails[item.id]
                )
                    .task {
                        if item.isFolder {
                            await libraryViewModel.fetchThumbnails(for: item)
                        }
                    }
                    .onTapGesture {
                        onItemTap(item)
                    }
                    .driveItemContextMenu(
                        for: item,
                        isDownloaded: libraryViewModel.downloadedComics[item.id] != nil,
                        isOfflineMode: libraryViewModel.isOfflineMode,
                        onBulkDownload: onBulkDownload,
                        onDownloadSingle: onDownloadSingle,
                        onDownloadFrom: onDownloadFrom
                    )
            }
        }
    }
}

// MARK: - Context Menu

/// フォルダ/アーカイブ用の長押しコンテキストメニュー
struct DriveItemContextMenuModifier: ViewModifier {
    let item: DriveItem
    let isDownloaded: Bool
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
                if !isDownloaded {
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
        isOfflineMode: Bool,
        onBulkDownload: @escaping (DriveItem) -> Void,
        onDownloadSingle: @escaping (DriveItem) -> Void,
        onDownloadFrom: @escaping (DriveItem) -> Void
    ) -> some View {
        modifier(DriveItemContextMenuModifier(
            item: item,
            isDownloaded: isDownloaded,
            isOfflineMode: isOfflineMode,
            onBulkDownload: onBulkDownload,
            onDownloadSingle: onDownloadSingle,
            onDownloadFrom: onDownloadFrom
        ))
    }
}
