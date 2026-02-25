// BulkDownloadManager.swift
// GD-MangaReader
//
// 一括ダウンロード処理を管理するマネージャー

import Foundation
import GoogleAPIClientForREST_Drive
import SwiftUI

/// 一括ダウンロード全体の進行状態を管理
@MainActor
@Observable
final class BulkDownloadManager {
    
    private(set) var isDownloading: Bool = false
    private(set) var currentCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var targetFolderId: String?
    
    private var downloadTask: Task<Void, Never>?
    
    var onDownloadUpdate: (() -> Void)?
    
    init() {}
    
    // MARK: - Methods
    
    /// 指定フォルダ内のZIP/アーカイブを一括処理
    func downloadSeries(
        folder: DriveItem,
        driveService: DriveService,
        authorizer: (any GTMSessionFetcherAuthorizer)?,
        accessToken: String?,
        onComplete: @escaping (_ failedCount: Int) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard !isDownloading else { return }
        isDownloading = true
        targetFolderId = folder.id
        currentCount = 0
        totalCount = 0
        
        downloadTask = Task {
            defer {
                resetState()
            }
            
            do {
                // 1. フォルダ内の全ファイルを取得（再帰ではなくフラットな一覧）
                var allItems: [DriveItem] = []
                var token: String? = nil
                repeat {
                    let result = try await driveService.listFiles(in: folder.id, pageToken: token)
                    allItems.append(contentsOf: result.items)
                    token = result.nextPageToken
                } while token != nil
                
                // 2. アーカイブのみ抽出
                let archives = allItems.filter { $0.isArchive }
                
                // 3. 未ダウンロードのものだけ抽出
                let pendingArchives = archives.filter { archive in
                    if let existing = try? LocalStorageService.shared.findComic(byDriveFileId: archive.id),
                       existing.status == .completed {
                        return false
                    }
                    return true
                }
                
                totalCount = pendingArchives.count
                
                if totalCount == 0 || Task.isCancelled {
                    onComplete(0)
                    return
                }
                
                // 4. ダウンロード実行 (並列処理)
                var failedCount = 0
                await withTaskGroup(of: Bool.self) { group in
                    let maxConcurrentTasks = 3 // 同時ダウンロード数
                    var activeTasks = 0
                    
                    for archive in pendingArchives {
                        if Task.isCancelled { break }
                        
                        if activeTasks >= maxConcurrentTasks {
                            if let success = await group.next(), !success {
                                failedCount += 1
                            }
                            activeTasks -= 1
                        }
                        
                        activeTasks += 1
                        group.addTask {
                            let result: Bool = await MainActor.run {
                                let downloader = DownloaderViewModel(driveService: driveService)
                                downloader.configure(with: authorizer, accessToken: accessToken)
                                return true
                            }
                            
                            // To actually use DownloaderViewModel methods outside MainActor, we should probably just rely on isolation. 
                            // Since downloadAndExtract is async, it might be safe to call it if it's annotated properly.
                            // But wait, if downloader is on MainActor, calling downloader.downloadAndExtract will hop to MainActor.
                            // Let's instantiate and configure on MainActor, then call the async function.
                            let downloaderResult = await MainActor.run {
                                let downloader = DownloaderViewModel(driveService: driveService)
                                downloader.configure(with: authorizer, accessToken: accessToken)
                                return downloader
                            }
                            let extractionResult = await downloaderResult.downloadAndExtract(item: archive)
                            
                            await MainActor.run {
                                self.currentCount += 1
                                self.onDownloadUpdate?()
                            }
                            return extractionResult != nil
                        }
                    }
                    
                    // 残りのタスクを待機
                    for await success in group {
                        if !success { failedCount += 1 }
                    }
                }
                
                if !Task.isCancelled {
                    onComplete(failedCount)
                }
                
            } catch {
                onError(error)
            }
        }
    }
    
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }
    
    func resetState() {
        isDownloading = false
        currentCount = 0
        totalCount = 0
        targetFolderId = nil
        downloadTask = nil
    }
}
