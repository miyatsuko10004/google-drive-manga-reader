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
            ForEach(libraryViewModel.filteredItems) { item in
                DriveItemGridCell(
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
