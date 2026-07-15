import SwiftUI

struct DriveItemGridView: View {
    let gridColumns: [GridItem]
    let libraryViewModel: LibraryViewModel
    let onItemTap: (DriveItem) -> Void
    let onBulkDownload: (DriveItem) -> Void
    let onDownloadSingle: (DriveItem) -> Void
    let onDownloadFrom: (DriveItem) -> Void

    private var downloadQueue: DownloadQueueManager { .shared }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(libraryViewModel.displayItems) { item in
                // onTapGestureではなくButtonで包み、押下中の視覚フィードバックを付ける
                Button {
                    onItemTap(item)
                } label: {
                    DriveItemGridCell(
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
