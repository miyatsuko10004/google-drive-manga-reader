import SwiftUI

struct DriveItemListView: View {
    let libraryViewModel: LibraryViewModel
    @Binding var selectedFolderForBulk: DriveItem?
    @Binding var showingBulkDownloadConfirmation: Bool
    let onItemTap: (DriveItem) -> Void
    
    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(libraryViewModel.filteredItems) { item in
                DriveItemListRow(
                    item: item,
                    isBulkDownloading: (libraryViewModel.isBulkDownloading && item.id == libraryViewModel.bulkDownloadTargetFolderId),
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
                    .onLongPressGesture {
                        if item.isFolder {
                            selectedFolderForBulk = item
                            showingBulkDownloadConfirmation = true
                        }
                    }
            }
        }
    }
}
